#!/bin/bash

PVC_FILE=$1
if [[ -z "$PVC_FILE" ]]; then
    echo "Must provide the name of a PVC.yaml"
    exit 1
fi

declare -r PVC_FILE_PATH=${DEMO_HOME}/kube/tekton/pipelines/${PVC_FILE}

declare -r PVC_NAME=$(cat ${PVC_FILE_PATH} | grep "name: "| cut -f 4 -d " ")
if [[ -z "$PVC_NAME" ]]; then
    echo "Could not find a PVC name in ${PVC_FILE_PATH}"
    exit 1
fi

echo "Deleting pods that have mounted $PVC_NAME in current project"
oc delete pods $(oc describe pvc/$PVC_NAME | grep "Mounted By" -A40 | sed "s/ //ig" | sed "s/MountedBy://ig")

echo "Deleting the pvc"
oc delete -f ${PVC_FILE_PATH}

echo "Recreating the pvc"
oc create -f ${PVC_FILE_PATH}