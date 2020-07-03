#!/bin/bash

set -e -u -o pipefail
declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)
declare PRJ_PREFIX="petclinic"
declare COMMAND="help"
declare SKIP_STAGING_PIPELINE=""
declare USER=""
declare PASSWORD=""
declare slack_webhook_url=""

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
      SKIP_STAGING_PIPELINE=$1;
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

  info "Create pull secret for redhat registry"
  $DEMO_HOME/scripts/util-create-pull-secret.sh registry-redhat-io --project $cicd_prj -u $USER -p $PASSWORD

  # import the s2i builder image that will be used to build our petclinic app (use the local reference policy so that projects
  # referencing this from outside this project don't need to have credentials to the source registry)
  info "import petclinic s2i image"
  oc import-image -n $cicd_prj tomcat8-builder --from=registry.redhat.io/jboss-webserver-3/webserver31-tomcat8-openshift:1.4 \
    --reference-policy='local' --confirm

  info "Configure service account permissions for builder"
  oc policy add-role-to-user system:image-puller system:serviceaccount:$dev_prj:builder -n $cicd_prj

  info "Configure service account permissions for pipeline"
  oc policy add-role-to-user edit system:serviceaccount:$cicd_prj:pipeline -n $dev_prj
  oc policy add-role-to-user edit system:serviceaccount:$cicd_prj:pipeline -n $stage_prj

  info "Deploying CI/CD infra to $cicd_prj namespace"
  oc apply -R -f $DEMO_HOME/kube/cd -n $cicd_prj
  GOGS_HOSTNAME=$(oc get route gogs -o template --template='{{.spec.host}}' -n $cicd_prj)

  info "Deploying pipeline and tasks to $cicd_prj namespace"
  oc apply -f $DEMO_HOME/kube/tekton/tasks --recursive -n $cicd_prj
  oc apply -f $DEMO_HOME/kube/tekton/config -n $cicd_prj
  oc apply -f $DEMO_HOME/kube/tekton/pipelines/pipeline-pvc.yaml -n $cicd_prj
  oc apply -f $DEMO_HOME/kube/tekton/pipelines/pipeline-source-pvc.yaml -n $cicd_prj
  
  if [[ -z "${slack_webhook_url}" ]]; then
    info "NOTE: No slack webhook url is set.  You can add this later by running oc create secret generic slack-webhook-secret."
  else
    oc create secret generic slack-webhook-secret --from-literal=url=${slack_webhook_url}
  fi

  info "Deploying dev and staging pipelines"
  if [[ -z "$SKIP_STAGING_PIPELINE" ]]; then
    oc process -f $DEMO_HOME/kube/tekton/pipelines/petclinic-stage-pipeline-tomcat-template.yaml -p PROJECT_NAME=$cicd_prj \
      -p DEVELOPMENT_PROJECT=$dev_prj -p STAGING_PROJECT=$stage_prj | oc apply -f - -n $cicd_prj
  else
    info "Skipping deploy to staging pipeline at user's request"
  fi
  sed "s/demo-dev/$dev_prj/g" $DEMO_HOME/kube/tekton/pipelines/petclinic-dev-pipeline-tomcat-workspace.yaml | oc apply -f - -n $cicd_prj
  
  # Install pipeline resources
  sed "s/demo-dev/$dev_prj/g" $DEMO_HOME/kube/tekton/resources/petclinic-image.yaml | oc apply -f - -n $cicd_prj
  
  # FIXME: Decide which repo we want to trigger/pull from
  # sed "s#https://github.com/spring-projects/spring-petclinic#http://$GOGS_HOSTNAME/gogs/spring-petclinic.git#g" $DEMO_HOME/kube/tekton/resources/petclinic-git.yaml | oc apply -f - -n $cicd_prj
  oc apply -f $DEMO_HOME/kube/tekton/resources/petclinic-git.yaml -n $cicd_prj

  # Install pipeline triggers
  oc apply -f $DEMO_HOME/kube/tekton/triggers --recursive -n $cicd_prj

  info "Initiatlizing git repository in Gogs and configuring webhooks"
  sed "s/@HOSTNAME/$GOGS_HOSTNAME/g" $DEMO_HOME/kube/config/gogs-configmap.yaml | oc create -f - -n $cicd_prj
  oc rollout status deployment/gogs -n $cicd_prj
  oc create -f $DEMO_HOME/kube/config/gogs-init-taskrun.yaml -n $cicd_prj

  info "Configure nexus repo"
  $SCRIPT_DIR/util-config-nexus.sh -n $cicd_prj -u admin -p admin123

  # Leave user in cicd project
  oc project $cicd_prj

  cat <<-EOF

############################################################################
############################################################################

  CI/CD project is installed! 

  NOTE: Your pipeline cannot currently be run from the UI due to its reliance on a (maven) workspace.
  Instead you must kick of your pipeline in one of the following ways:

  A. File

    1) oc apply -f $DEMO_HOME/kube/tekton/pipelinerun/petclinic-dev-pipeline-tomcat-run.yaml
       - This will use the defined pipeline resources and the maven workspace
  
  B. Github Deploy

    1) Get the github trigger address

    2) Log into your github repo and update the settings to point to the webhook (see also
       $DEMO_HOME/docs/Walkthrough.adoc)
  
  C. Gogs Deploy

  1) Go to spring-petclinic Git repository in Gogs:
     http://$GOGS_HOSTNAME/gogs/spring-petclinic.git
  
  2) Log into Gogs with username/password: gogs/gogs
      
  3) Edit a file in the repository and commit to trigger the pipeline

Finally, you can check the pipeline run logs in Dev Console or Tekton CLI:
     
    \$ tkn pipeline logs petclinic-dev-pipeline-tomcat -f -n $cicd_prj

############################################################################
############################################################################
EOF
}

command.start() {
  oc create -f runs/pipeline-deploy-dev-run.yaml -n $cicd_prj
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