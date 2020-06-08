#!/bin/bash

declare PROJECT_BASE="petclinic"

# declare an array
arrSuffix=( "dev" "stage" "cicd" )
 
# for loop that iterates over each element in arr
for i in "${arrSuffix[@]}"
do
    echo "Deleting $i"
    oc delete project "${PROJECT_BASE}-${i}"
done