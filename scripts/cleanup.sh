#!/bin/bash

set -Eeuo pipefail

declare -r SCRIPT_DIR=$(cd -P $(dirname $0) && pwd)
declare PROJECT_PREFIX="petclinic"

display_usage() {
cat << EOF
$0: Tekton Comparison Demo Uninstall --

  Usage: ${0##*/} [ OPTIONS ]
  
    -f         [optional] Full uninstall, removing pre-requisites
    -p <TEXT>  [optional] Project prefix to use.  Defaults to petclinic
EOF
}

get_and_validate_options() {
  # Transform long options to short ones
    #   for arg in "$@"; do
    #     shift
    #     case "$arg" in
    #       "--long-x") set -- "$@" "-x" ;;
    #       "--long-y") set -- "$@" "-y" ;;
    #       *)        set -- "$@" "$arg"
    #     esac
    #   done

    
    # parse options
    while getopts ':p:fh' option; do
        case "${option}" in
            p  ) p_flag=true; PROJECT_PREFIX="${OPTARG}";;
            f  ) full_flag=true;;
            h  ) display_usage; exit;;
            \? ) printf "%s\n\n" "  Invalid option: -${OPTARG}" >&2; display_usage >&2; exit 1;;
            :  ) printf "%s\n\n%s\n\n\n" "  Option -${OPTARG} requires an argument." >&2; display_usage >&2; exit 1;;
        esac
    done
    shift "$((OPTIND - 1))"

    if [[ -z "${PROJECT_PREFIX}" ]]; then
        printf '%s\n\n' 'ERROR - PROJECT_PREFIX must not be null' >&2
        display_usage >&2
        exit 1
    fi
}


remove-operator()
{
    OPERATOR_NAME=$1
    OPERATOR_PRJ=${2:-openshift-operators}

    echo "Uninstalling operator: ${OPERATOR_NAME} from project ${OPERATOR_PRJ}"
    # NOTE: there is intentionally a space before "currentCSV" in the grep since without it f.currentCSV will also be matched which is not what we want
    CURRENT_CSV=$(oc get sub ${OPERATOR_NAME} -n ${OPERATOR_PRJ} -o yaml | grep " currentCSV:" | sed "s/.*currentCSV: //")
    oc delete sub ${OPERATOR_NAME} -n ${OPERATOR_PRJ} || true
    oc delete csv ${CURRENT_CSV} -n ${OPERATOR_PRJ} || true

    # Attempt to remove any orphaned install plan named for the csv
    oc get installplan | grep ${CURRENT_CSV} | awk {'print $1'} 2>/dev/null | xargs oc delete installplan 
}

remove-crds() 
{
    API_NAME=$1

    oc get crd -oname | grep "${API_NAME}" | xargs oc delete
}

main() 
{
    # import common functions
    . $SCRIPT_DIR/common-func.sh

    trap 'error' ERR
    trap 'cleanup' EXIT SIGTERM
    trap 'interrupt' SIGINT

    get_and_validate_options "$@"

    # declare an array
    arrSuffix=( "dev" "stage" "cicd" "uat")
    
    # for loop that iterates over each element in arr
    for i in "${arrSuffix[@]}"
    do
        echo "Deleting $i"
        oc delete project "${PROJECT_PREFIX}-${i}" || true
    done

    if [[ -n "${full_flag:-}" ]]; then
        remove-operator argocd-operator argocd || true

        remove-crds argo || true

        oc delete project argocd || true

        # uninstall openshift pipelines
        remove-operator openshift-pipelines-operator || true
    fi
}

main "$@"