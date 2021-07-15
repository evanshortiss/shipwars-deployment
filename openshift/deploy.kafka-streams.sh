#!/usr/bin/env bash

NAMESPACE=${NAMESPACE:-shipwars}
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

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

# Check that the bind script has been run
oc get kafkaconnection

if [ $? -eq 1 ]; then
  echo "No kafkaconnection CustomResource was found in the $NAMESPACE project."
  echo "Please run deploy.kafka-bind.sh and retry this script."
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

# Force user to choose a the kafka instance
rhoas kafka use

KAFKA_BOOTSTRAP_SERVERS=$(rhoas kafka describe | jq .bootstrap_server_host -r)

echo "Deploy Quarkus Kafka Streams applications and visualisation UI"

# Deploy the enricher Kafka Streams application. This performs a join between
# a shot and player record to create a more informative enriched shot record
oc process -f "${DIR}/shipwars-streams-shot-enricher.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS}" | oc create -f -

# An aggregator implemented in Kafka Streams that tracks how often a given
# cell coordinate is hit by players (AI and human) thereby capturing a shot
# distribution. This also exposes an HTTP server sent events endpoint that can
# stream shots to clients in realtime
oc process -f "${DIR}/shipwars-streams-shot-distribution.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS}" | oc create -f -

# Another aggregator that tracks the shots fired for each game in series.
# This can be used to replay games and/or write them somewhere for long term
# permanent storage, e.g S3 buckets or DB
oc process -f "${DIR}/shipwars-streams-match-aggregates.yml" \
-p NAMESPACE="${NAMESPACE}" \
-p KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS}" | oc create -f -

# Deploy the replay UI, and instruct it to use the internal match aggregates
# Quarkus/Kafka Streams application API
oc new-app quay.io/evanshortiss/shipwars-replay-ui \
-l "app.kubernetes.io/part-of=shipwars-analysis" \
-e REPLAY_SERVER="http://shipwars-streams-match-aggregates:8080" \
--name shipwars-replay

oc expose svc shipwars-replay

# A UI to see shots play out in realtime.
oc new-app quay.io/evanshortiss/s2i-nodejs-nginx~https://github.com/evanshortiss/shipwars-visualisations \
--name shipwars-visualisations \
-l "app.kubernetes.io/part-of=shipwars-analysis,app.openshift.io/runtime=nginx" \
--build-env STREAMS_API_URL="https://$(oc get route shipwars-streams-shot-distribution -o jsonpath='{.spec.host}')/shot-distribution/stream"

oc expose svc shipwars-visualisations
