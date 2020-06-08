#!/bin/bash

oc get project petclinic-dev 2>/dev/null || oc new-project petclinic-dev

oc new-app openshift/mysql-persistent --name petclinic-mysql -p MYSQL_ROOT_PASSWORD=petclinic -p MYSQL_USER=pc \
    -p DATABASE_SERVICE_NAME=petclinic-mysql -p MYSQL_DATABASE=petclinic -p MYSQL_PASSWORD=petclinic

sleep 1

oc wait --for=condition=Available dc -l app=petclinic-mysql --timeout=5m

# create the database and user for our service to use
oc run mysql-client --image=mysql:5.7 --restart=Never --rm=true --attach=true --wait=true \
    -- mysql -h petclinic-mysql -uroot -ppetclinic \
    -e "GRANT ALL PRIVILEGES ON petclinic.* TO 'pc'@'%';"