#!/usr/bin/env bash

if ! command -v rhoas &> /dev/null
then
    echo "Please install rhoas CLI to use this script"
    exit 1
fi

if ! command -v jq &> /dev/null
then
    echo "Please install jq CLI to use this script"
    exit 1
fi

rhoas login > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Logged in to OpenShift Streams for Apache Kafka."
else
  echo ""
  echo "Login failed for OpenShift Streams for Apache Kafka."
  exit 1
fi

KAFKA_COUNT=$(rhoas kafka list -o json | jq '.total')

if [ "0" == "$KAFKA_COUNT" ]; then
  echo ""
  echo "Please create a Kafka instance using 'rhoas kafka create' and retry this script."
  exit 1
fi

# Force user to choose a kafka instance
rhoas kafka use

# Create topics for game events (sent by the game server)
rhoas kafka topic create --name shipwars-matches --partitions 3
rhoas kafka topic create --name shipwars-players --partitions 3
rhoas kafka topic create --name shipwars-attacks --partitions 3
rhoas kafka topic create --name shipwars-bonuses --partitions 3
rhoas kafka topic create --name shipwars-results --partitions 3

# Create topics used by Kafka Streams
rhoas kafka topic create --name shipwars-attacks-lite --partitions 3
rhoas kafka topic create --name shipwars-streams-shots-aggregate --partitions 3
rhoas kafka topic create --name shipwars-streams-matches-aggregate --partitions 3

echo ""
echo "Created required topics for the Shipwars game."
