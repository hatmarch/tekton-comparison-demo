#!/bin/bash

declare USER=""
declare PASSWORD=""
declare SECRET_NAME=""
declare PROJECT_NAME="$(oc project -q)"

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--user)
      USER=$2
      shift 2
      ;;
    -p|--password)
      PASSWORD=$2
      shift 2
      ;;
    --project)
      PROJECT_NAME=$2
      shift 2
      ;;
    *)
      if [ -z "$SECRET_NAME" ]; then
        SECRET_NAME=$1
        shift
      else
        echo "Secret name provided twice."
        exit 1
      fi
      ;;
  esac
done

if [ -z "$USER" ]; then
    echo "Must specify a user for registry.redhat.io"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "Must specify a password for registry.redhat.io"
    exit 1
fi

if [ -z "${SECRET_NAME}" ]; then
    SECRET_NAME="redhat-registry-pull"
fi

if [ -z "${PROJECT_NAME}" ]; then
    echo "Invalid or null project name specified"
    exit 1
fi

echo "Using user: $USER and password: $PASSWORD for secret $SECRET_NAME in project ${PROJECT_NAME}"

# Create a pull secret in the current project redhat.registry.io 
oc create secret docker-registry $SECRET_NAME \
    --docker-server=registry.redhat.io \
    --docker-username="$USER" \
    --docker-password="$PASSWORD" \
    --docker-email=mhildenb@redhat.com -n $PROJECT_NAME

# This should supposedly use --for=pull as its a pull secret, however in OpenShift 4.3 that doesn't appear to work exclusively
oc secrets link pipeline $SECRET_NAME -n $PROJECT_NAME --for=pull
oc secrets link pipeline $SECRET_NAME -n $PROJECT_NAME 


