# Event Broker

Edge Core can publish lifecycle events to a message broker. This is opt-in — the broker is deployed separately and Edge Admin connects to it via env vars.

## Supported Brokers

| Broker             | Adapter   | Notes                                                                    |
| ------------------ | --------- | ------------------------------------------------------------------------ |
| **NATS JetStream** | `nats_js` | Recommended. Lightweight, durable, built-in replay.                      |
| **Redpanda**       | `kafka`   | Recommended Kafka-compatible option. No JVM, lighter than vanilla Kafka. |
| **Apache Kafka**   | `kafka`   | Use if you already run Kafka. Any Kafka-compatible broker works.         |

> **Important:** The `nats_js` adapter requires JetStream to be enabled on the NATS server. Vanilla NATS (no JetStream) is not supported — messages would be lost when no consumer is subscribed.

## Quick Start

Pick a broker and start it alongside your core:

```bash
# NATS JetStream (recommended)
docker compose -f cloud.yml -f ../event_brokers/nats_js.yml up -d

# Redpanda
docker compose -f cloud.yml -f ../event_brokers/redpanda.yml up -d

# Apache Kafka
docker compose -f cloud.yml -f ../event_brokers/kafka.yml up -d
```

Then enable the broker in your `.env`:

```bash
# NATS JetStream
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats_js
EVENT_BROKER_URLS=nats://edge_event_broker:4222

# Redpanda or Kafka
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=kafka
EVENT_BROKER_URLS=edge_event_broker:9092
```

## Files

```
event_brokers/
├── nats_js.yml         — NATS JetStream + NUI web UI
├── redpanda.yml        — Redpanda + Redpanda Console
├── kafka.yml           — Apache Kafka (KRaft) + Kafka UI
└── config/
    ├── nats.conf       — NATS server config (JetStream, TLS + cluster blocks commented out)
    └── nui-context.json — NUI pre-configured connection to edge_event_broker
```

## Env Vars Reference

```bash
EVENT_BROKER_ENABLED=true|false          # gate — all else ignored when false (default: false)
EVENT_BROKER_ADAPTER=nats_js|kafka       # required when enabled
EVENT_BROKER_URLS=...                    # NATS: nats://host:port  |  Kafka: host:port

# NATS auth (optional)
EVENT_BROKER_NATS_TOKEN=

# Kafka/Redpanda auth (optional)
EVENT_BROKER_KAFKA_USERNAME=
EVENT_BROKER_KAFKA_PASSWORD=
EVENT_BROKER_KAFKA_SASL_MECHANISM=plain  # plain (default) | scram_sha_256 | scram_sha_512
EVENT_BROKER_KAFKA_SSL=true              # enable TLS for external/public brokers

# Core identifier — included in every event envelope (default: "default")
CORE_NAME=prod-us
```

## Bring Your Own Broker

These compose files are for convenience. If you already run a broker, skip them entirely — just point `EVENT_BROKER_URLS` at your existing instance. Any Kafka-compatible broker (Confluent Cloud, Aiven, MSK, Upstash, etc.) works with `EVENT_BROKER_ADAPTER=kafka`. Any NATS server with JetStream enabled works with `EVENT_BROKER_ADAPTER=nats_js`.

## Events Published

See the AsyncAPI spec at `GET /api/asyncapi` (or browse `/asyncdoc`) for the full event schema. Edge Admin publishes 14 event types across three domains:

- **Node** — registered, reregistered, version changed, status changed, cluster changed, update triggered, deleted
- **Execution** — created, sent, completed, cancelled, expired
- **Self-update** — created, completed

All events follow the [CloudEvents 1.0](https://cloudevents.io) spec.
