#!/bin/bash

set -e -u -o pipefail
declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)
declare PRJ_PREFIX="petclinic"
declare COMMAND="help"
declare USER=""
declare PASSWORD=""
declare CREATE_STAGING_PIPELINE=""

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
    --create-staging-pipeline)
      CREATE_STAGING_PIPELINE=$1;
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
  # oc get ns $dev_prj 2>/dev/null  || { 
  #   oc new-project $dev_prj
  #}
  oc get ns $stage_prj 2>/dev/null  || { 
    oc new-project $stage_prj 
  }

  info "Configure service account permissions for pipeline"
  oc policy add-role-to-user edit system:serviceaccount:$cicd_prj:pipeline -n $stage_prj

  # Create staging pipeline
  if [[ -z "$CREATE_STAGING_PIPELINE" ]]; then
    info "Creating the deploy to staging pipeline"
    oc process -f $DEMO_HOME/kube/tekton/pipelines/petclinic-stage-pipeline-tomcat-template.yaml -p PROJECT_NAME=$cicd_prj \
      -p DEVELOPMENT_PROJECT=$dev_prj -p STAGING_PROJECT=$stage_prj | oc apply -f - -n $cicd_prj
  else
    info "Skipping staging pipeline creation"
  fi
    
  # Start SQL Creation
  info "Deploying SQL Cluster"
  oc project $stage_prj
  $DEMO_HOME/scripts/create-sql-cluster.sh

  info "Deploying app to $stage_prj namespace"
  oc tag $dev_prj/petclinic:latest $stage_prj/petclinic:latest
  oc process -f $DEMO_HOME/kube/staging/staging-project-template.yaml -p STAGING_PROJECT=$stage_prj \
    -p APP_NAME=petclinic | oc apply -f - -n $stage_prj
  
  cat <<-EOF

Staging Project is Created
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