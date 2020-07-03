#!/bin/bash

export DEMO_HOME=$( cd "$(dirname "$0")/.." ; pwd -P )

alias cpr='tkn pr cancel $(tkn pr list -o name --limit 1 | cut -f 2 -d "/")'