#!/usr/bin/env bash
# deploy/local/compose/edge_event_broker/google_pubsub/init.sh
#
# Pub/Sub emulator bootstrap. Runs once via a one-shot init container that
# depends on the emulator being healthy. The emulator does NOT auto-create
# topics — we provision them ourselves.
#
# We hit the emulator's REST API directly with curl rather than `gcloud
# pubsub topics create`. gcloud's pubsub commands try to authenticate against
# real GCP for create/delete operations even with PUBSUB_EMULATOR_HOST set —
# only describe/list reliably route to the emulator. The emulator does serve
# REST on the same port as gRPC despite the docs implying gRPC-only.
#
# Creates three topics matching the production naming convention plus a pull
# subscription per topic so adapter publishes can be verified without standing
# up a separate consumer:
#
#   docker exec local_edge_event_broker_google_pubsub curl -s \
#     -X POST -H 'Content-Type: application/json' -d '{"maxMessages":10}' \
#     http://127.0.0.1:8085/v1/projects/edge-local/subscriptions/edge-nodes-events-debug:pull
#
# PUT topic + PUT subscription are idempotent — re-running returns the
# existing resource, safe across restarts.

set -euo pipefail

PROJECT="${PUBSUB_PROJECT_ID:-edge-local}"
HOST="${PUBSUB_EMULATOR_HOST:?PUBSUB_EMULATOR_HOST must be set}"
TOPICS=(edge-nodes-events edge-commands-events edge-self-updates-events edge-ssh-events)

api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sf -X "$method" -H 'Content-Type: application/json' \
      -d "$body" "http://${HOST}${path}"
  else
    curl -sf -X "$method" -H 'Content-Type: application/json' \
      "http://${HOST}${path}"
  fi
}

for topic in "${TOPICS[@]}"; do
  api PUT "/v1/projects/${PROJECT}/topics/${topic}" >/dev/null
  echo "pubsub topic ready: $topic"
done

for topic in "${TOPICS[@]}"; do
  sub="${topic}-debug"
  body=$(printf '{"topic":"projects/%s/topics/%s"}' "$PROJECT" "$topic")
  api PUT "/v1/projects/${PROJECT}/subscriptions/${sub}" "$body" >/dev/null
  echo "pubsub debug subscription ready: $sub (subscribed to $topic)"
done

echo "google_pubsub emulator init complete (project=$PROJECT)"
