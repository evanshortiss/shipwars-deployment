#!/usr/bin/env bash

NAMESPACE=${NAMESPACE:-shipwars}

if ! command -v oc &> /dev/null
then
    echo "Please install oc CLI to use this script"
    exit
fi

if ! command -v rhoas &> /dev/null
then
    echo "Please install rhoas CLI to use this script"
    exit
fi

if ! command -v jq &> /dev/null
then
    echo "Please install jq CLI to use this script"
    exit
fi

oc project $NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Using project $NAMESPACE on cluster: $(oc whoami --show-server)"
else
  echo "Failed to select $NAMESPACE project using the 'oc project' command."
  echo "Did you forget to set the NAMESPACE variable, or have not run deploy.sh yet?"
  exit 1
fi

rhoas login > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Logged in to OpenShift Streams for Apache Kafka."
else
  echo "Login failed for OpenShift Streams for Apache Kafka."
  exit 1
fi

KAFKA_COUNT=$(rhoas kafka list -o json | jq '.total')

if [ "0" == "$KAFKA_COUNT" ]; then
  echo "Please create a Kafka instance using 'rhoas kafka create' and retry this script"
fi

# Force user to choose a kafka instance
rhoas kafka use

# Check topics exist (yes, this is basic but should help)
rhoas kafka topic list -o json | jq -r '.items[].name' | grep 'shipwars-attacks'
if [ $? -eq 1 ]; then
  echo "Please run the configure-rhosak.sh script in the root of this repository then retry this script."
fi

# Connect the chosen instance to the cluster
rhoas cluster connect -n $NAMESPACE
rhoas cluster bind --app-name shipwars-game-server

echo "Deploy Quarkus Kafka Streams application and visualisation UI"
oc process -f "${DIR}/shipwars-streams-shot-distribution.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p KAFKA_BOOTSTRAP_SERVERS=$(rhoas kafka describe | jq .bootstrapServerHost -r) | oc create -f -

oc new-app quay.io/evanshortiss/s2i-nodejs-nginx~https://github.com/evanshortiss/shipwars-visualisations \
--name shipwars-visualisations \
--build-env BUILD_OUTPUT_DIR=dist \
--build-env STREAMS_API_URL="https://$(oc get route shipwars-streams-shot-distribution -o jsonpath='{.spec.host}')/shot-distribution/stream"
