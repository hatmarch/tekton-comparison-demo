#!/bin/bash

set -e -u -o pipefail

declare prj_argo=argocd

wait_for_crd()
{
    local CRD=$1
    local PROJECT=$(oc project -q)
    if [[ "${2:-}" ]]; then
        # set to the project passed in
        PROJECT=$2
    fi

    # Wait for the CRD to appear
    while [ -z "$(oc get $CRD 2>/dev/null)" ]; do
        sleep 1
    done 
    sleep 2
    oc wait --for=condition=Established $CRD --timeout=6m -n $PROJECT
}

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: preview
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get ns $prj_argo 2>/dev/null  || { 
    oc new-project $prj_argo 
}
sleep 2

cat <<EOF | oc apply -n $prj_argo -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: argocd-operator
spec:
  channel: alpha
  name: argocd-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

wait_for_crd "crd/argocds.argoproj.io" $prj_argo

cat <<EOF | oc apply -n $prj_argo -f -
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: argocd
spec:
  server:
    route:
      enabled: true
  dex:
    openShiftOAuth: true
EOF

oc rollout status deployment/argocd-server -n $prj_argo


