PHASE=$1
if [[ -z "$PHASE" ]]; then
    PHASE="Succeeded"
fi

oc get pods -n petclinic-cicd -l \
tekton.dev/pipelineRun=$(tkn pr list -o name --limit 1 | cut -f 2 -d "/") \
-o jsonpath="{range .items[?(@.status.phase=='${PHASE}')]}{'Task: '}{.metadata.labels['tekton\.dev/pipelineTask']}{'\n'}{'\t'}{'Pod: '}{.metadata.name}{' '}{.status.phase}{'\n'}{range .status.containerStatuses[*]}{'\t\t'}{'Container: '}{.name}{'\t\t'}{'finishedAt: '}{.state.terminated.finishedAt}{'\n'}{end}{end}{'\n'}" \
| sed "s/$(date -u +%F)T//g"