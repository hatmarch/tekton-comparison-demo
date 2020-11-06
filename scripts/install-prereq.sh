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
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: ocp-4.5
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc get ns $prj_argo 2>/dev/null  || { 
    oc new-project $prj_argo 
}
sleep 2

# install operator group
cat <<EOF | oc apply -n $prj_argo -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: argocd-og
spec:
  targetNamespaces:
  - $prj_argo
EOF

cat <<EOF | oc apply -n $prj_argo -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: argocd-operator
spec:
  channel: alpha
  installPlanApproval: Automatic
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

declare ARGO_SERVER_DEPLOY="deployment/argocd-server"

echo -n "Waiting for the ArgoCD server to appear."
while [ -z "$(oc get ${ARGO_SERVER_DEPLOY} -n ${prj_argo} 2>/dev/null)" ]; do
    sleep 1
    echo -n "."
done 
echo "found!"

oc rollout status ${ARGO_SERVER_DEPLOY} -n $prj_argo

declare giteaop_prj=gpte-operators
echo "Installing gitea operator in ${giteaop_prj}"
oc apply -f $DEMO_HOME/kube/gitea/gitea-crd.yaml
oc apply -f $DEMO_HOME/kube/gitea/gitea-cluster-role.yaml
oc get ns $giteaop_prj 2>/dev/null  || { 
    oc new-project $giteaop_prj --display-name="GPTE Operators"
}

# create the service account and give necessary permissions
oc get sa gitea-operator -n $giteaop_prj 2>/dev/null || {
  oc create sa gitea-operator -n $giteaop_prj
}
oc adm policy add-cluster-role-to-user gitea-operator system:serviceaccount:$giteaop_prj:gitea-operator

# install the operator to the gitea project
oc apply -f $DEMO_HOME/kube/gitea/gitea-operator.yaml -n $giteaop_prj
sleep 2
oc rollout status deploy/gitea-operator -n $giteaop_prj
