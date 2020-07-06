#!/bin/bash

set -e -u -o pipefail
declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)

declare COMMAND="start"
declare PROJECT="petclinic-cicd"

while (( "$#" )); do
  case "$1" in
    --stop)
      COMMAND="stop"
      shift
      ;;
    -p|--project)
      PROJECT=$2
      shift 2
      ;;
    *) 
      echo "Error: Unsupported flag $1"
      exit 1
      ;;
  esac
done

valid_command() {
  local fn=$1; shift
  [[ $(type -t "$fn") == "function" ]]
}

command.start() {
    oc port-forward svc/sonarqube 9000:9000 -n $PROJECT &
    oc port-forward svc/nexus 8081:8081 -n $PROJECT &
}

command.stop() {
    kill $(ps -aux | grep "oc port-forward" | sed -n "s/ \+/ /gp" | cut -f 2 -d ' ')
}

main() {
    local fn="command.$COMMAND"
  valid_command "$fn" || {
    echo "invalid command '$COMMAND'"
  }

  $fn
  return $?
}

main