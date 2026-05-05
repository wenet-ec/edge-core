# Event Broker

Edge Core can publish lifecycle events to a message broker. This is opt-in — Edge Admin connects to whatever broker you point it at via env vars, the broker itself is your responsibility.

Edge Core publishes and forgets — it has no knowledge of consumers. All messages follow the [CloudEvents 1.0](https://cloudevents.io) spec, with `type` and `corename` promoted to broker-native message attributes / headers / partition keys / topics so subscribers can filter without parsing the body.

## Adapters

| Adapter                            | Protocol family               | Works against                                                                                                                                               |
| ---------------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nats`                             | NATS / NATS JetStream         | Any NATS server. JetStream-enabled servers gain durable log + replay via `EVENT_BROKER_NATS_JETSTREAM=true`.                                                |
| `kafka`                            | Kafka wire protocol           | Apache Kafka, Redpanda, Confluent Cloud, Aiven, AWS MSK, Azure Event Hubs, Upstash, Redpanda Cloud, etc.                                                    |
| `amqp091` <br/>(alias: `rabbitmq`) | AMQP 0-9-1                    | Any AMQP 0-9-1 broker — RabbitMQ, LavinMQ (single-node or clustered), AmazonMQ for RabbitMQ, CloudAMQP.                                                     |
| `redis`                            | Redis Pub/Sub                 | Any Redis instance. Fire-and-forget — no durability, no replay.                                                                                             |
| `mqtt`                             | MQTT 5                        | Any MQTT 5 broker — EMQX, Mosquitto, HiveMQ, AWS IoT Core, Azure Event Grid (MQTT broker mode), VerneMQ, NanoMQ, etc. (adapter hardcodes `proto_ver: :v5`). |
| `aws_sns`                          | AWS SNS REST API              | AWS SNS (managed). Publishes to four pre-provisioned domain topics; subscribers filter via subscription filter policies.                                    |
| `google_pubsub`                    | Google Cloud Pub/Sub REST API | Google Cloud Pub/Sub (managed). Same shape as SNS — four pre-provisioned domain topics, subscription filter expressions on attributes.                      |

Pick whichever adapter matches a broker your stack already runs. There is no recommended default.

**Not currently supported, on the table if there's demand:** AMQP 1.0 (different wire protocol from AMQP 0-9-1 despite the similar name — covers ActiveMQ, Azure Service Bus, IBM MQ, Solace) and Apache Pulsar. If you have a concrete use case for either, [open an issue](https://github.com/wenet-ec/edge-core/issues) — adapters are tractable to add and we prioritise based on real user demand.

## Quick Start

For self-hosted brokers, this directory ships compose files you can layer onto the cloud stack:

```bash
# Self-hosted (one of):
docker compose -f cloud.yml -f ../event_brokers/nats.yml up -d
docker compose -f cloud.yml -f ../event_brokers/redpanda.yml up -d
docker compose -f cloud.yml -f ../event_brokers/kafka.yml up -d
docker compose -f cloud.yml -f ../event_brokers/rabbitmq.yml up -d
docker compose -f cloud.yml -f ../event_brokers/redis.yml up -d
docker compose -f cloud.yml -f ../event_brokers/emqx.yml up -d
docker compose -f cloud.yml -f ../event_brokers/mosquitto.yml up -d
```

Managed cloud services (AWS SNS, Google Cloud Pub/Sub) have no compose file — provision the topics in your account first (see [Managed Cloud Services](#managed-cloud-services)).

Either way, then enable the adapter via env vars:

```bash
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=<one of the adapter ids above>

# ...plus the adapter-specific endpoint / project / region — see Configuration below.
CORE_NAME=prod-us   # optional; included in every event envelope (default: "default")
```

## Configuration

Endpoint env var name carries the shape:

- `_URLS` (plural) — adapter accepts a comma-separated cluster list (NATS, Kafka).
- `_URL` (singular) — adapter takes a single endpoint (RabbitMQ, Redis, MQTT).
- Managed services have no endpoint var — region / project + auth locate the service.

### NATS

```bash
EVENT_BROKER_ADAPTER=nats
EVENT_BROKER_NATS_URLS=nats://host:4222     # comma-separated for cluster; tls:// for public/external brokers
EVENT_BROKER_NATS_JETSTREAM=true            # optional — enable JetStream durable log (default: false)

# Auth — pick one (mutually exclusive, token takes precedence):
EVENT_BROKER_NATS_TOKEN=
EVENT_BROKER_NATS_USERNAME=
EVENT_BROKER_NATS_PASSWORD=
EVENT_BROKER_NATS_NKEY_SEED=                # standalone or paired with JWT
EVENT_BROKER_NATS_JWT=                      # alongside NKEY_SEED
```

### Kafka / Redpanda

```bash
EVENT_BROKER_ADAPTER=kafka
EVENT_BROKER_KAFKA_URLS=host:9092           # comma-separated for cluster; no scheme

EVENT_BROKER_KAFKA_USERNAME=                # optional
EVENT_BROKER_KAFKA_PASSWORD=
EVENT_BROKER_KAFKA_SASL_MECHANISM=plain     # plain (default) | scram_sha_256 | scram_sha_512
EVENT_BROKER_KAFKA_SSL=true                 # required for public/external brokers
```

### AMQP 0-9-1 (RabbitMQ-compatible)

```bash
EVENT_BROKER_ADAPTER=amqp091                            # alias `rabbitmq` also accepted
EVENT_BROKER_RABBITMQ_URL=amqp://user:pass@host:5672    # embed credentials in URL
EVENT_BROKER_RABBITMQ_SSL=true                          # required for external brokers (CloudAMQP, etc.)
```

Events publish to a durable topic exchange `edge.events` with routing key = event type. Works against RabbitMQ, LavinMQ, AmazonMQ for RabbitMQ, CloudAMQP — anything speaking AMQP 0-9-1.

### Redis

```bash
EVENT_BROKER_ADAPTER=redis
EVENT_BROKER_REDIS_URL=redis://:password@host:6379      # embed credentials in URL; rediss:// for TLS
EVENT_BROKER_REDIS_SSL=true                             # required for external brokers (Redis Cloud, Upstash, etc.)
```

Channel = event type. Use `SUBSCRIBE edge.node.registered` for exact match, `PSUBSCRIBE edge.*` for wildcards. No durability — if no subscriber is connected, the message is gone.

### MQTT

```bash
EVENT_BROKER_ADAPTER=mqtt
EVENT_BROKER_MQTT_URL=host:1883                         # single host:port; no scheme
EVENT_BROKER_MQTT_QOS=1                                 # 0|1|2 (default 1, at-least-once with broker ACK)

# Auth — pick one mode (mutually exclusive, JWT precedence over username/password):
EVENT_BROKER_MQTT_JWT=                                  # JWT bearer in CONNECT password slot
EVENT_BROKER_MQTT_USERNAME=
EVENT_BROKER_MQTT_PASSWORD=

# TLS:
EVENT_BROKER_MQTT_SSL=true                              # required for external brokers
EVENT_BROKER_MQTT_CACERT_FILE=                          # custom CA bundle / pinning
EVENT_BROKER_MQTT_CLIENT_CERT_FILE=                     # mTLS — requires SSL=true
EVENT_BROKER_MQTT_CLIENT_KEY_FILE=                      # mTLS — requires SSL=true
```

Topic = event type with `.` rewritten to `/` (e.g. `edge.node.registered` → `edge/node/registered`) so MQTT segment wildcards (`+`, `#`) work as expected.

### AWS SNS

```bash
EVENT_BROKER_ADAPTER=aws_sns
EVENT_BROKER_AWS_SNS_REGION=us-east-1
EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX=arn:aws:sns:us-east-1:123456789012:    # account-scoped ARN prefix

# Auth — standard AWS credential chain (env vars / shared credentials file / instance profile / IRSA):
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=                          # optional, when assuming an IAM role via STS
```

### Google Cloud Pub/Sub

```bash
EVENT_BROKER_ADAPTER=google_pubsub
EVENT_BROKER_GOOGLE_PUBSUB_PROJECT=my-project-123
EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX=                                  # optional, e.g. "edge-prod-"

# Auth — standard GCP credential chain via goth:
GOOGLE_APPLICATION_CREDENTIALS=/etc/gcp/sa.json    # service-account JSON path; unset on GKE/GCE for Workload Identity / metadata server
```

## Self-Hosted Brokers

```
event_brokers/
├── nats.yml            — NATS (JetStream enabled) + NUI web UI
├── redpanda.yml        — Redpanda + Redpanda Console
├── kafka.yml           — Apache Kafka (KRaft) + Kafka UI
├── rabbitmq.yml        — RabbitMQ + Management UI
├── redis.yml           — Redis (no UI)
├── emqx.yml            — EMQX (MQTT) + built-in dashboard
├── mosquitto.yml       — Mosquitto (MQTT, minimal, no UI)
└── config/             — server configs (TLS / cluster blocks commented out by default)
```

These files are convenience scaffolding for new deployments. If you already run a broker matching one of the protocol families above, skip the compose file and point the relevant `EVENT_BROKER_*_URL(S)` directly at it.

### Reusing the bundled Netmaker broker

Edge Core ships an MQTT broker (EMQX or Mosquitto) inside the Netmaker stack — it's used by Netmaker for VPN control-plane traffic. Pointing the event broker at this same instance is **not recommended**: lifecycle, auth, capacity tuning, and operational dashboards all become entangled with VPN internals. Run a dedicated event broker.

## Managed Cloud Services

For managed services there's no compose file — the service exists in your cloud account and Edge Admin connects to it. Both supported services follow the same pattern: pre-provision the domain topics, grant publish access to the principal Edge Admin runs as, point the adapter at it.

The topic names are fixed:

```
edge-nodes-events           ← all node lifecycle events
edge-commands-events        ← all command execution events
edge-self-updates-events    ← all self-update events
```

Edge Admin promotes `type` and `corename` from each event envelope into broker-native message attributes. Subscribers filter on those attributes server-side using the cloud's own filter syntax — see the cloud's docs for the syntax (filter policies for SNS, filter expressions for Pub/Sub).

### AWS SNS

|                      |                                                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Adapter**          | `aws_sns`                                                                                                                                                       |
| **Topics to create** | `edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`, `edge-ssh-events`                                                                      |
| **IAM action**       | `sns:Publish` on the four topic ARNs                                                                                                                            |
| **Auth**             | Standard AWS credential chain via `ex_aws`. Prefer **IRSA** on EKS / instance profile on EC2; static keys via env vars are an escape hatch.                     |
| **Subscriptions**    | SQS queue, Lambda, HTTPS endpoint — your choice. SNS itself stores nothing.                                                                                     |
| **Filter syntax**    | [SNS subscription filter policies](https://docs.aws.amazon.com/sns/latest/dg/sns-subscription-filter-policies.html) — JSON, matched against message attributes. |

```bash
for t in edge-nodes-events edge-commands-events edge-self-updates-events; do
  aws sns create-topic --name "$t" --region us-east-1
done
```

Minimal IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sns:Publish",
      "Resource": [
        "arn:aws:sns:us-east-1:123456789012:edge-nodes-events",
        "arn:aws:sns:us-east-1:123456789012:edge-commands-events",
        "arn:aws:sns:us-east-1:123456789012:edge-self-updates-events"
      ]
    }
  ]
}
```

Filter policy examples:

```json
{"type": [{"prefix": "edge.node."}]}                       // all node events
{"type": ["edge.command_execution.completed"]}             // specific event type
{"corename": ["prod-us"]}                                  // events from one core
```

### Google Cloud Pub/Sub

|                      |                                                                                                                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Adapter**          | `google_pubsub`                                                                                                                                                                                                                |
| **Topics to create** | `edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`, `edge-ssh-events` (prefix optional via `EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX`)                                                                  |
| **IAM role**         | `roles/pubsub.publisher` on the four topics                                                                                                                                                                                    |
| **Auth**             | Standard GCP credential chain via `goth`. Prefer **Workload Identity** on GKE / metadata server on GCE; service-account JSON via `GOOGLE_APPLICATION_CREDENTIALS` is an escape hatch.                                          |
| **Subscriptions**    | Pull, push (HTTPS / Cloud Run), BigQuery, Cloud Storage. Pub/Sub buffers per subscription (default 7-day retention, max 31).                                                                                                   |
| **Filter syntax**    | [Pub/Sub subscription filters](https://cloud.google.com/pubsub/docs/subscription-message-filter#filtering_syntax) — query language, matched against message attributes. Set on subscription creation; cannot be changed later. |

```bash
for t in edge-nodes-events edge-commands-events edge-self-updates-events; do
  gcloud pubsub topics create "$t" --project=my-project-123
done
```

Minimal per-topic role binding:

```bash
for t in edge-nodes-events edge-commands-events edge-self-updates-events; do
  gcloud pubsub topics add-iam-policy-binding "$t" \
    --member=serviceAccount:edge-admin@my-project-123.iam.gserviceaccount.com \
    --role=roles/pubsub.publisher --project=my-project-123
done
```

Filter expression examples:

```
attributes.type = "edge.node.status_changed"
hasPrefix(attributes.type, "edge.node.")
attributes.corename = "prod-us" AND hasPrefix(attributes.type, "edge.command_execution.")
```

## Events Published

See the AsyncAPI spec at `GET /api/asyncapi` (or browse `/asyncdoc`) for the full event schema. Edge Admin publishes events across:

- **Node lifecycle** — registration, version changes, health/status transitions, cluster moves, self-update triggers, deletion.
- **Command execution lifecycle** — execution created, delivered to agent, completed/cancelled/expired.
- **Self-update lifecycle** — request created and batch completed.

All events follow the [CloudEvents 1.0](https://cloudevents.io) spec.
