#!/bin/bash

set -Ee -u -o pipefail
declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)
declare PRJ_PREFIX="petclinic"
declare COMMAND="help"
declare SKIP_STAGING_PIPELINE=""
declare SKIP_JENKINS=""
declare USER=""
declare PASSWORD=""
declare slack_webhook_url=""
declare INSTALL_PREREQ=""
declare ARGO_OPERATOR_PRJ="argocd"

valid_command() {
  local fn=$1; shift
  [[ $(type -t "$fn") == "function" ]]
}

info() {
    printf "\n# INFO: $@\n"
}

err() {
  printf "\n# ERROR: $1\n"
  exit 1
}

while (( "$#" )); do
  case "$1" in
    install|uninstall|start)
      COMMAND=$1
      shift
      ;;
    -p|--project-prefix)
      PRJ_PREFIX=$2
      shift 2
      ;;
    --user)
      USER=$2
      shift 2
      ;;
    --password)
      PASSWORD=$2
      shift 2
      ;;
    --slack-webhook-url)
      slack_webhook_url=$2
      shift 2
      ;;
    --skip-staging-pipeline)
      SKIP_STAGING_PIPELINE=$1
      shift 1
      ;;
    --skip-jenkins)
      SKIP_JENKINS=$1
      shift 1
      ;;
    -i|--install-prereq)
      INSTALL_PREREQ=true
      shift 1
      ;;
    --)
      shift
      break
      ;;
    -*|--*)
      err "Error: Unsupported flag $1"
      ;;
    *) 
      break
  esac
done

declare -r dev_prj="$PRJ_PREFIX-dev"
declare -r stage_prj="$PRJ_PREFIX-stage"
declare -r cicd_prj="$PRJ_PREFIX-cicd"
declare -r uat_prj="$PRJ_PREFIX-uat"

command.help() {
  cat <<-EOF

  Usage:
      demo [command] [options]
  
  Example:
      demo install --project-prefix mydemo
  
  COMMANDS:
      install                        Sets up the demo and creates namespaces
      uninstall                      Deletes the demo namespaces
      start                          Starts the demo pipeline
      help                           Help about this command

  OPTIONS:
      -p|--project-prefix [string]   Prefix to be added to demo project names e.g. PREFIX-dev
      --user [string]                User name for the Red Hat registry
      --password [string]            Password for the Red Hat registry
      -i|--install-prereq            Whether to install supporting operators and custom resources
      --skip-jenkins                 Skip the installation of the Jenkins CI/CD plane
EOF
}

command.install() {
  oc version >/dev/null 2>&1 || err "no oc binary found"

  if [[ -z "${DEMO_HOME:-}" ]]; then
    err '$DEMO_HOME not set'
  fi

  info "Creating namespaces $cicd_prj, $dev_prj, $stage_prj"
  oc get ns $cicd_prj 2>/dev/null  || { 
    oc new-project $cicd_prj 
  }
  oc get ns $dev_prj 2>/dev/null  || { 
    oc new-project $dev_prj
  }
  oc get ns $stage_prj 2>/dev/null  || { 
    oc new-project $stage_prj 
  }
  oc get ns $uat_prj 2>/dev/null || {
    oc new-project $uat_prj
  }

  if [[ -n "${INSTALL_PREREQ}" ]]; then
    $SCRIPT_DIR/install-prereq.sh ${ARGO_OPERATOR_PRJ}
  fi

  info "Create pull secret for redhat registry"
  $DEMO_HOME/scripts/util-create-pull-secret.sh registry-redhat-io --project $cicd_prj -u $USER -p $PASSWORD

  # import the s2i builder image that will be used to build our petclinic app (use the local reference policy so that projects
  # referencing this from outside this project don't need to have credentials to the source registry)
  info "import petclinic s2i image"
  oc import-image -n $cicd_prj tomcat8-builder --from=registry.redhat.io/jboss-webserver-3/webserver31-tomcat8-openshift:1.4 \
    --reference-policy='local' --confirm

  # Petclinic builder (leveraged by Jenkins and created image-stream referred to by the petclinic deployment)
  oc new-build --name=petclinic --image-stream=$cicd_prj/tomcat8-builder --binary=true -n $cicd_prj
  oc import-image -n $cicd_prj petclinic --from=quay.io/mhildenb/tekton-petclinic-initial:latest \
    --reference-policy='local' --confirm

  info "Configure service account permissions for pipeline"
  oc policy add-role-to-user edit system:serviceaccount:$cicd_prj:pipeline -n $dev_prj
  oc policy add-role-to-user edit system:serviceaccount:$cicd_prj:pipeline -n $stage_prj

  info "Deploying CI/CD infra to $cicd_prj namespace"
  oc apply -R -f $DEMO_HOME/kube/cd -n $cicd_prj
  
  info "Deploying pipeline and tasks to $cicd_prj namespace"
  oc apply -f $DEMO_HOME/kube/tekton/tasks --recursive -n $cicd_prj
  oc apply -R -f $DEMO_HOME/kube/tekton/config -n $cicd_prj

  info "Creating workspaces volumes in $cicd_prj namespace"
  oc apply -R -f $DEMO_HOME/kube/tekton/workspaces -n $cicd_prj
  
  if [[ -z "${slack_webhook_url}" ]]; then
    info "NOTE: No slack webhook url is set.  You can add this later by running oc create secret generic slack-webhook-secret."
  else
    oc delete secret slack-webhook-secret -n $cicd_prj || true
    oc create secret generic slack-webhook-secret --from-literal=url=${slack_webhook_url} -n $cicd_prj
  fi

  info "Deploying dev and staging pipelines"
  if [[ -z "$SKIP_STAGING_PIPELINE" ]]; then
    oc process -f $DEMO_HOME/kube/tekton/pipelines/petclinic-stage-pipeline-tomcat-template.yaml -p PROJECT_NAME=$cicd_prj \
      -p DEVELOPMENT_PROJECT=$dev_prj -p STAGING_PROJECT=$stage_prj -p CICD_PROJECT=$cicd_prj | oc apply -f - -n $cicd_prj
  else
    info "Skipping deploy to staging pipeline at user's request"
  fi
  sed "s/demo-dev/$dev_prj/g" $DEMO_HOME/kube/tekton/pipelines/petclinic-dev-pipeline-tomcat-workspace.yaml | oc apply -f - -n $cicd_prj
  
  # Install pipeline resources
  sed "s/demo-cicd/$cicd_prj/g" $DEMO_HOME/kube/tekton/resources/petclinic-image.yaml | oc apply -f - -n $cicd_prj
  
  # FIXME: Decide which repo we want to trigger/pull from
  # sed "s#https://github.com/spring-projects/spring-petclinic#http://$GOGS_HOSTNAME/gogs/spring-petclinic.git#g" $DEMO_HOME/kube/tekton/resources/petclinic-git.yaml | oc apply -f - -n $cicd_prj
  oc apply -f $DEMO_HOME/kube/tekton/resources/petclinic-git.yaml -n $cicd_prj

  # Install pipeline triggers
  oc apply -f $DEMO_HOME/kube/tekton/triggers --recursive -n $cicd_prj

  info "Initiatlizing git repository in gitea and configuring webhooks"
  oc apply -f $DEMO_HOME/kube/gitea/gitea-server-cr.yaml -n $cicd_prj
  oc wait --for=condition=Running Gitea/gitea-server -n $cicd_prj --timeout=6m
  echo -n "Waiting for gitea deployment to appear..."
  while [[ -z "$(oc get deploy gitea -n $cicd_prj 2>/dev/null)" ]]; do
    echo -n "."
    sleep 1
  done
  echo "done!"
  oc rollout status deploy/gitea -n $cicd_prj

  # patch the created gitea service to select the proper pod
 # oc patch svc/gitea -p '{"spec":{"selector":{"app":"gitea"}}}' -n $cicd_prj

  oc create -f $DEMO_HOME/kube/gitea/gitea-init-taskrun.yaml -n $cicd_prj
  # output the logs of the latest task
  tkn tr logs -L -f -n $cicd_prj

  info "Configure nexus repo"
  $SCRIPT_DIR/util-config-nexus.sh -n $cicd_prj -u admin -p admin123

  info "Seed maven cache in workspace"
  oc apply -n $cicd_prj -f $DEMO_HOME/kube/config/copy-to-workspace-task.yaml 
  oc create -n $cicd_prj -f $DEMO_HOME/kube/config/seed-cache-task-run.yaml
  tkn tr logs -L -f -n $cicd_prj

  # Create the target apps
  # dev
  # Create a petclinic deployment based on the image stream in the CICD project (see above)
  oc new-app --name=petclinic --allow-missing-images --image-stream=$cicd_prj/petclinic -n $dev_prj

  # NOTE: With the latest version of the oc client (4.5 and above) new-app creates deployments by default, which is what 
  # we want to happen here as the pipeline now depends on this behavior
  sleep 2
  if [[ -z "$(oc get deploy/petclinic -n $dev_prj 2>/dev/null)" ]]; then
    echo "oc new-app did not create Deployments.  Update to latest version of openshift client"
    exit 1
  fi
  oc expose svc/petclinic -n $dev_prj
  
  # stage
  oc new-app petclinic --allow-missing-images -n $stage_prj
  # NOTE: With the latest version of the oc client (4.5 and above) new-app creates deployments by default, which is what 
  # we want to happen here as the pipeline now depends on this behavior
  sleep 2
  if [[ -z "$(oc get deploy/petclinic -n $stage_prj 2>/dev/null)" ]]; then
    echo "oc new-app did not create Deployments.  Update to latest version of openshift client"
    exit 1
  fi
  oc expose deploy/petclinic --port=8080 -n $stage_prj
  oc expose svc/petclinic -n $stage_prj

  echo "Setting image-puller permissions for other projecct service accounts into $cicd_prj"
  arrPrjs=( ${dev_prj} ${stage_prj} ${uat_prj} )
  arrSAs=( default pipeline builder )
  for prj in "${arrPrjs[@]}"; do
    for sa in "${arrSAs[@]}"; do
      oc adm policy add-role-to-user system:image-puller system:serviceaccount:${prj}:${sa} -n ${cicd_prj}
    done
  done

  #
  # Configure ArgoCD
  # 
  echo "Configuring ArgoCD for project $uat_prj"
  argocd_pwd=$(oc get secret argocd-cluster -n ${ARGO_OPERATOR_PRJ} -o jsonpath='{.data.admin\.password}' | base64 -d)
  argocd_url=$(oc get route argocd-server -n ${ARGO_OPERATOR_PRJ} -o template --template='{{.spec.host}}')
  argocd login $argocd_url --username admin --password $argocd_pwd --insecure

  # FIXME: Shouldn't this line be codified in the gitops repo?  This might be necessary for bootstrapping, but after that...
  oc policy add-role-to-user edit system:serviceaccount:${ARGO_OPERATOR_PRJ}:argocd-application-controller -n $uat_prj
  argocd app create petclinic-argo --repo http://gitea.$cicd_prj:3000/gogs/petclinic-config --path . --dest-namespace $uat_prj --dest-server https://kubernetes.default.svc \
    --directory-recurse --revision uat --sync-policy automated --self-heal --auto-prune
  
  # NOTE: it's setup to autosync so this is not necessary
  # argocd app sync petclinic-argo

  echo "\n\nArgoCD URL: $argocd_url\nUser: admin\nPassword: $argocd_pwd"

  # install jenkins (unless explicited told to skip)
  if [[ -z "${SKIP_JENKINS}" ]]; then
    echo "Installing Jenkins elements"
    $SCRIPT_DIR/create-jenkins-cicd.sh deploy --project-prefix ${PRJ_PREFIX}
  else
    echo "Skipping Jenkins installation"
  fi

  # Leave user in cicd project
  oc project $cicd_prj

  cat <<-EOF
#####################################
Installation finished successfully!
#####################################
EOF
}

command.start() {
  oc create -f $DEMO_HOME/kube/tekton/pipelinerun/petclinic-dev-pipeline-tomcat-workspace-run.yaml -n $cicd_prj
  tkn pr logs -L -f -n $cicd_prj
}

command.uninstall() {
  oc delete project $dev_prj $stage_prj $cicd_prj
}

main() {
  local fn="command.$COMMAND"
  valid_command "$fn" || {
    err "invalid command '$COMMAND'"
  }

  cd $SCRIPT_DIR
  $fn
  return $?
}

main