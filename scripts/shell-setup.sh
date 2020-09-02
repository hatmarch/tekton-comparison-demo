#!/bin/bash

export DEMO_HOME=$( cd "$(dirname "$0")/.." ; pwd -P )

alias cpr='tkn pr cancel $(tkn pr list -o name --limit 1 | cut -f 2 -d "/")'
alias ctr='tkn tr cancel $(tkn tr list -o name --limit 1 | cut -f 2 -d "/")'

# shorthand for creating a pipeline run file and watching the logs
pr () {
    FILE="$1"
    oc create -f $FILE && tkn pr logs -L -f
}

tskr () {
    FILE="$1"
    oc create -f $FILE && tkn tr logs -L -f
}

aws-up() {
    local CLUSTER_NAME=${1:-${CLUSTERNAME}}
    if [[ -z "${CLUSTER_NAME}" ]]; then
        echo "Must provide a cluster name either as parameter or in environment variable `CLUSTERNAME`"
        return 1
    fi

    local AWS_REGION=${REGION}
    if [[ -z "${AWS_REGION}" ]]; then
        echo "Must provide a region by way of REGION environment variable"
        return 1
    fi

    aws ec2 start-instances --instance-ids --region=${AWS_REGION} \
        $(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --output text --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_NAME}-*" "Name=instance-state-name,Values=stopped")
}

aws-down() {
    local CLUSTER_NAME=${1:-${CLUSTERNAME}}
    if [[ -z "$CLUSTER_NAME" ]]; then
        echo "Must provide a cluster name either as parameter or in environment variable `CLUSTERNAME`"
        return 1
    fi

    local AWS_REGION=${REGION}
    if [[ -z "${AWS_REGION}" ]]; then
        echo "Must provide a region by way of REGION environment variable"
        return 1
    fi

    aws ec2 stop-instances --instance-ids --region ${AWS_REGION} \
        $(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --output text --filters "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_NAME}-*" "Name=instance-state-name,Values=running") 
}
