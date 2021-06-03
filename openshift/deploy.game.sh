#!/usr/bin/env bash

NAMESPACE=${NAMESPACE:-shipwars}
CONFIG_MAP_NAME=${CONFIG_MAP_NAME:-shipwars-shared-config}
LOG_LEVEL=${LOG_LEVEL:-info}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

oc project $NAMESPACE > /dev/null 2>&1

if [ $? -ne 0 ]
then
  echo "Creating ${NAMESPACE} project..."
  # Project did not exist, so we need to create it
  oc new-project $NAMESPACE > /dev/null 2>&1
fi

echo "Creating ${CONFIG_MAP_NAME} ConfigMap..."
oc process -f "${DIR}/config-map.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p CONFIG_MAP_NAME="${CONFIG_MAP_NAME}" \
-p LOG_LEVEL="${LOG_LEVEL}" | oc create -f -

echo "Creating services, deployments, and routes..."
oc process -f "${DIR}/shipwars-move-server.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p CONFIG_MAP_NAME="${CONFIG_MAP_NAME}" | oc create -f -

oc process -f "${DIR}/shipwars-game-server.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p CONFIG_MAP_NAME="${CONFIG_MAP_NAME}" | oc create -f -

oc process -f "${DIR}/shipwars-bot-server.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p CONFIG_MAP_NAME="${CONFIG_MAP_NAME}" | oc create -f -

oc process -f "${DIR}/shipwars-client.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p CONFIG_MAP_NAME="${CONFIG_MAP_NAME}" | oc create -f -
