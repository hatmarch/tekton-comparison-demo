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