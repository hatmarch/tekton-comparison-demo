#!/bin/bash

#set -e -u -o pipefail

#################################################################
# Functions for Managing Sonatype Nexus                         #
#                                                               #
# Authors:                                                      #
# - Jorge Morales        https://github.com/jorgemoralespou     #
# - Siamak Sadeghianfar  https://github.com/siamaksade          #
#                                                               #
#################################################################


#
# add_nexus3_repo [repo-id] [repo-url] [nexus-username] [nexus-password] [nexus-url]
#
function add_nexus3_repo() {
  local _REPO_ID=$1
  local _REPO_URL=$2
  local _NEXUS_USER=$3
  local _NEXUS_PWD=$4
  local _NEXUS_URL=$5

  read -r -d '' _REPO_JSON << EOM
{
  "name": "$_REPO_ID",
  "type": "groovy",
  "content": "repository.createMavenProxy('$_REPO_ID','$_REPO_URL')"
}
EOM

 echo "addming repo"
  # Post Nexus 3.8
  curl -v -H "Accept: application/json" -H "Content-Type: application/json" -d "$_REPO_JSON" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/"
  curl -v -X POST -H "Content-Type: text/plain" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/$_REPO_ID/run"

echo "done with repo"
}

# https://gist.github.com/nblair/1a0e05713c3edb7e5360c2b0222c7623 and https://groups.google.com/a/glists.sonatype.com/forum/#!topic/nexus-users/dvv7NlHN0qw
function add_nexus3_hosted_repo() {
  local _REPO_ID=$1
  local _NEXUS_USER=$2
  local _NEXUS_PWD=$3
  local _NEXUS_URL=$4

  read -r -d '' _REPO_JSON << EOM
{
  "name": "${_REPO_ID}",
  "type": "groovy",
  "content": "import org.sonatype.nexus.repository.storage.WritePolicy; import org.sonatype.nexus.repository.maven.VersionPolicy; import org.sonatype.nexus.repository.maven.LayoutPolicy; repository.createMavenHosted('$_REPO_ID','default',true, VersionPolicy.RELEASE,WritePolicy.ALLOW,LayoutPolicy.STRICT)"
}
EOM
  # Post Nexus 3.8
  curl -v -H "Accept: application/json" -H "Content-Type: application/json" -d "$_REPO_JSON" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/"
  curl -v -X POST -H "Content-Type: text/plain" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/${_REPO_ID}/run"
}


#
# delete_nexus3_group_repo
#
function delete_nexus3_repo() {
    local _GROUP_ID=$1
      local _NEXUS_USER=$2
  local _NEXUS_PWD=$3
  local _NEXUS_URL=$4

read -r -d '' _REPO_JSON << EOM
{
  "name": "${_GROUP_ID}_delete_script",
  "type": "groovy",
  "content": "repository.getRepositoryManager().delete('$_GROUP_ID');"
}
EOM

  curl -v -H "Accept: application/json" -H "Content-Type: application/json" -d "$_REPO_JSON" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/"
  curl -v -X POST -H "Content-Type: text/plain" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/${_GROUP_ID}_delete_script/run"

}


#
# add_nexus3_group_repo [comma-separated-repo-ids] [group-id] [nexus-username] [nexus-password] [nexus-url]
#
function add_nexus3_group_repo() {
  local _REPO_IDS=$1
  local _GROUP_ID=$2
  local _NEXUS_USER=$3
  local _NEXUS_PWD=$4
  local _NEXUS_URL=$5

  read -r -d '' _REPO_JSON << EOM
{
  "name": "$_GROUP_ID",
  "type": "groovy",
  "content": "repository.createMavenGroup('$_GROUP_ID', '$_REPO_IDS'.split(',').toList())"
}
EOM

  # Post Nexus 3.8
  curl -v -H "Accept: application/json" -H "Content-Type: application/json" -d "$_REPO_JSON" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/"
  curl -v -X POST -H "Content-Type: text/plain" -u "$_NEXUS_USER:$_NEXUS_PWD" "${_NEXUS_URL}/service/rest/v1/script/$_GROUP_ID/run"
}


declare PROJECT_NAME="PetClinic"
declare NEXUS_USER=""
declare NEXUS_PWD=""

while (( "$#" )); do
  case "$1" in
    -n|--name)
        PROJECT_NAME=$2
        shift 2
        ;;
    -u|--user)
        NEXUS_USER=$2
        shift 2
        ;;
    -p|--password)
        NEXUS_PWD=$2
        shift 2
        ;;
    -*|--*)
        echo "Error: Unsupported flag $1"
        ;;
    *)
    break
  esac
done
  
  #curl -o $DEMO_HOME/nexus-functions -s https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/scripts/nexus-functions
  # source $DEMO_HOME/kube/cd/nexus/nexus_functions.sh

  oc port-forward svc/nexus 8081:8081 -n $PROJECT_NAME &

  # wait for port-forwarding to start
  sleep 5
  NEXUS_URL=http://localhost:8081

  delete_nexus3_repo maven-releases $NEXUS_USER $NEXUS_PWD $NEXUS_URL
  add_nexus3_hosted_repo maven-releases $NEXUS_USER $NEXUS_PWD $NEXUS_URL

  add_nexus3_repo spring-io https://repo.spring.io/milestone/ $NEXUS_USER $NEXUS_PWD $NEXUS_URL
  add_nexus3_repo redhat-ea https://maven.repository.redhat.com/earlyaccess/all/ $NEXUS_USER $NEXUS_PWD $NEXUS_URL

  delete_nexus3_repo maven-public $NEXUS_USER $NEXUS_PWD $NEXUS_URL
  add_nexus3_group_repo maven-central,maven-releases,maven-snapshots,redhat-ea,spring-io maven-public $NEXUS_USER $NEXUS_PWD $NEXUS_URL

  # stop port forwarding
  kill $!