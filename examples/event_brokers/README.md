# Event Broker

Edge Core can publish lifecycle events to a message broker. This is opt-in — the broker is deployed separately and Edge Admin connects to it via env vars.

## Supported Brokers

| Broker           | Adapter    | Notes                                                                                                       |
| ---------------- | ---------- | ----------------------------------------------------------------------------------------------------------- |
| **NATS**         | `nats`     | Lightweight. Pure pub/sub by default. Set `EVENT_BROKER_NATS_JETSTREAM=true` for durable log with replay.   |
| **Redpanda**     | `kafka`    | Recommended Kafka-compatible option. No JVM, lighter than vanilla Kafka.                                    |
| **Apache Kafka** | `kafka`    | Use if you already run Kafka. Any Kafka-compatible broker works.                                            |
| **RabbitMQ**     | `rabbitmq` | Topic exchange `edge.events`, routing key = event type. Consumer queue durability is the consumer's choice. |
| **Redis**        | `redis`    | Fire-and-forget pub/sub. No durability or replay — pick only when consumers are always-on.                  |

Pick whichever broker fits your existing stack — there is no recommended default.

> **NATS modes:** By default, NATS runs as pure pub/sub — messages are lost when no subscriber is connected. Set `EVENT_BROKER_NATS_JETSTREAM=true` to enable JetStream durable log with replay. Both modes use the same `nats` adapter and the same NATS server binary; JetStream is just a server feature flag.

## Quick Start

Pick a broker and start it alongside your core:

```bash
# NATS
docker compose -f cloud.yml -f ../event_brokers/nats_js.yml up -d

# Redpanda
docker compose -f cloud.yml -f ../event_brokers/redpanda.yml up -d

# Apache Kafka
docker compose -f cloud.yml -f ../event_brokers/kafka.yml up -d

# RabbitMQ
docker compose -f cloud.yml -f ../event_brokers/rabbitmq.yml up -d

# Redis
docker compose -f cloud.yml -f ../event_brokers/redis.yml up -d
```

Then enable the broker in your `.env`:

```bash
# NATS pub/sub
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats
EVENT_BROKER_URLS=nats://edge_event_broker:4222

# NATS JetStream (durable log)
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats
EVENT_BROKER_URLS=nats://edge_event_broker:4222
EVENT_BROKER_NATS_JETSTREAM=true

# Redpanda or Kafka
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=kafka
EVENT_BROKER_URLS=edge_event_broker:9092

# RabbitMQ
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=rabbitmq
EVENT_BROKER_URLS=amqp://edge_event_broker:5672

# Redis
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=redis
EVENT_BROKER_URLS=redis://edge_event_broker:6379
```

## Files

```
event_brokers/
├── nats_js.yml         — NATS (JetStream enabled) + NUI web UI
├── redpanda.yml        — Redpanda + Redpanda Console
├── kafka.yml           — Apache Kafka (KRaft) + Kafka UI
├── rabbitmq.yml        — RabbitMQ + Management UI
├── redis.yml           — Redis (fire-and-forget pub/sub, no UI)
└── config/
    ├── nats.conf                  — NATS server config (JetStream, TLS + cluster blocks commented out)
    ├── nui-context.json           — NUI pre-configured connection to edge_event_broker
    ├── rabbitmq.conf              — RabbitMQ server config (TLS block commented out)
    └── rabbitmq_enabled_plugins   — enables management plugin
```

## Env Vars Reference

```bash
EVENT_BROKER_ENABLED=true|false          # gate — all else ignored when false (default: false)
EVENT_BROKER_ADAPTER=nats|kafka|rabbitmq|redis # required when enabled
EVENT_BROKER_URLS=...                    # NATS: nats://host:port  |  Kafka: host:port  |  RabbitMQ: amqp://host:port  |  Redis: redis://host:port

# NATS options (optional)
EVENT_BROKER_NATS_JETSTREAM=true         # enable durable JetStream log (default: false)
# Auth — pick one, mutually exclusive (token takes precedence):
EVENT_BROKER_NATS_TOKEN=                 # shared token
EVENT_BROKER_NATS_USERNAME=              # username + password
EVENT_BROKER_NATS_PASSWORD=
EVENT_BROKER_NATS_NKEY_SEED=            # NKey seed (standalone or with JWT)
EVENT_BROKER_NATS_JWT=                   # JWT credential — used alongside NKEY_SEED

# Kafka/Redpanda auth (optional)
EVENT_BROKER_KAFKA_USERNAME=
EVENT_BROKER_KAFKA_PASSWORD=
EVENT_BROKER_KAFKA_SASL_MECHANISM=plain  # plain (default) | scram_sha_256 | scram_sha_512
EVENT_BROKER_KAFKA_SSL=true              # enable TLS for external/public brokers

EVENT_BROKER_RABBITMQ_SSL=true           # enable TLS for external/public brokers (CloudAMQP, etc.)

EVENT_BROKER_REDIS_SSL=true              # enable TLS for external/public brokers (Redis Cloud, Upstash, etc.)

# Core identifier — included in every event envelope (default: "default")
CORE_NAME=prod-us
```

## Bring Your Own Broker

These compose files are for convenience. If you already run a broker, skip them entirely — just point `EVENT_BROKER_URLS` at your existing instance.

- Any Kafka-compatible broker (Confluent Cloud, Aiven, MSK, Upstash, etc.) works with `EVENT_BROKER_ADAPTER=kafka`.
- Any NATS server works with `EVENT_BROKER_ADAPTER=nats`; enable JetStream on the server and set `EVENT_BROKER_NATS_JETSTREAM=true` for durable delivery.
- Any RabbitMQ instance works with `EVENT_BROKER_ADAPTER=rabbitmq`; events are published to a durable topic exchange `edge.events` with routing key = event type.
- Any Redis instance works with `EVENT_BROKER_ADAPTER=redis`; Core publishes to channels matching the event type (`edge.node.registered`, etc.). Embed credentials in the URL: `redis://:password@host:port`.

## Events Published

See the AsyncAPI spec at `GET /api/asyncapi` (or browse `/asyncdoc`) for the full event schema. Edge Admin publishes 14 event types across three domains:

- **Node** — registered, reregistered, version changed, status changed, cluster changed, update triggered, deleted
- **Execution** — created, sent, completed, cancelled, expired
- **Self-update** — created, completed

All events follow the [CloudEvents 1.0](https://cloudevents.io) spec.
