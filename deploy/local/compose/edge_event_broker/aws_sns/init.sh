#!/usr/bin/env bash
# deploy/local/compose/edge_event_broker/aws_sns/init.sh
#
# LocalStack SNS bootstrap. Runs on every container start (mounted at
# /etc/localstack/init/ready.d/init.sh). create-topic / create-queue / subscribe
# are idempotent — re-running returns existing resources, safe across restarts.
#
# Creates three SNS topics matching the production naming convention, plus an
# SQS queue subscribed to each topic so adapter publishes can be verified
# without standing up a separate consumer:
#
#   awslocal sqs receive-message --queue-url <queue-url> --max-number-of-messages 10
#
# `awslocal` ships in the LocalStack image — same flags as `aws`, pre-pointed
# at http://localhost:4566. No --endpoint-url needed inside the container.

set -euo pipefail

TOPICS=(edge-nodes-events edge-commands-events edge-self-updates-events edge-ssh-events)

for topic in "${TOPICS[@]}"; do
  awslocal sns create-topic --name "$topic" >/dev/null
  echo "sns topic ready: $topic"
done

for topic in "${TOPICS[@]}"; do
  queue="${topic}-debug"
  awslocal sqs create-queue --queue-name "$queue" >/dev/null

  topic_arn=$(awslocal sns list-topics \
    --query "Topics[?ends_with(TopicArn, ':${topic}')].TopicArn | [0]" \
    --output text)
  if [[ -z "$topic_arn" || "$topic_arn" == "None" ]]; then
    echo "fatal: topic '$topic' not found after create-topic" >&2
    exit 1
  fi
  queue_url=$(awslocal sqs get-queue-url --queue-name "$queue" --output text)
  queue_arn=$(awslocal sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)

  awslocal sns subscribe \
    --topic-arn "$topic_arn" \
    --protocol sqs \
    --notification-endpoint "$queue_arn" \
    --attributes RawMessageDelivery=true >/dev/null

  echo "sqs debug subscription ready: $queue (subscribed to $topic)"
done

echo "localstack aws_sns init complete"
