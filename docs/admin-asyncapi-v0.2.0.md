# Edge Core AsyncAPI — v0.2.0

Event schema reference for all lifecycle events published by Edge Admin.

Interactive viewer: `/asyncdoc` on a running admin. Raw spec: `GET /api/asyncapi`.

---

## Overview

Edge Admin publishes lifecycle events to a configured message broker (NATS, Kafka/Redpanda, AMQP 0-9-1 (RabbitMQ-compatible), Redis, MQTT, AWS SNS, or Google Cloud Pub/Sub). All events follow the [CloudEvents 1.0](https://cloudevents.io) spec. Edge Admin publishes and forgets — it has no knowledge of consumers.

### Event Envelope

Every event is wrapped in a CloudEvents envelope:

```json
{
  "specversion": "1.0",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "source": "https://github.com/wenet-ec/edge-core",
  "type": "edge.node.registered",
  "time": "2026-04-14T10:00:00Z",
  "datacontenttype": "application/json",
  "corename": "prod-us",
  "data": { ... }
}
```

| Field             | Description                                                                                                                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `specversion`     | Always `"1.0"`                                                                                                                                                                                                                                   |
| `id`              | UUID v4 — unique per publish. Useful for exactly-once delivery dedup (broker retries). Not useful for semantic dedup of `node.status_changed` duplicates — those carry different `id`s. Use `(node_id, previous_status, status, time)` for that. |
| `source`          | Always `"https://github.com/wenet-ec/edge-core"`                                                                                                                                                                                                 |
| `type`            | Event type — doubles as NATS subject, RabbitMQ routing key, Redis channel, and MQTT topic (with `.` rewritten to `/` for MQTT — see tables below)                                                                                                |
| `time`            | When the state change happened in admin (ISO 8601)                                                                                                                                                                                               |
| `datacontenttype` | Always `"application/json"`                                                                                                                                                                                                                      |
| `corename`        | CloudEvents extension. Identifies the publishing core instance. Set via `CORE_NAME` env var (default: `"default"`)                                                                                                                               |
| `data`            | Full object snapshot at moment of event (see schemas below)                                                                                                                                                                                      |

---

## Subjects / Topics

### NATS

The `type` value is also the NATS subject. Subscription examples:

```
edge.node.>                       ← all node events
edge.node.status_changed          ← only status transitions (server-side filter)
edge.command_execution.completed  ← only completed executions
edge.>                            ← everything
```

**JetStream mode** (`EVENT_BROKER_NATS_JETSTREAM=true`): durable streams (one per domain) are auto-created on startup:

```
Stream: EDGE_NODES_EVENTS          captures: edge.node.> + edge.enrollment_key.>
Stream: EDGE_COMMANDS_EVENTS       captures: edge.command_execution.>
Stream: EDGE_SELF_UPDATES_EVENTS   captures: edge.self_update_request.>
Stream: EDGE_SSH_EVENTS            captures: edge.ssh_username.>
```

Retention is configured on the NATS server, not by Edge Core.

**Pub/sub mode** (default): messages are delivered to active subscribers only — no persistence. Missed messages are gone.

### Kafka / Redpanda

Four topics, one per domain:

| Topic                      | Partition key                                                   |
| -------------------------- | --------------------------------------------------------------- |
| `edge-nodes-events`        | `node_id` (or `enrollment_key_id` for enrollment events)        |
| `edge-commands-events`     | `command_execution_id`                                          |
| `edge-self-updates-events` | `self_update_request_id`                                        |
| `edge-ssh-events`          | `node_id` (verifications partition by the node attempting auth) |

Partition key ensures ordering per entity, parallel across entities. Filter by event type using the `type` field in the envelope.

### AMQP 0-9-1 (RabbitMQ-compatible)

Adapter id: `amqp091` (alias: `rabbitmq`). Works against any AMQP 0-9-1 broker — RabbitMQ, LavinMQ, AmazonMQ for RabbitMQ, CloudAMQP.

All events are published to a single durable topic exchange: `edge.events`. The routing key is the event `type` (e.g. `edge.node.registered`).

Binding examples:

```
edge.node.*                ← all node events
edge.node.status_changed   ← only status transitions
edge.command_execution.#   ← all command execution events
edge.#                     ← everything
```

Consumer queue durability is the consumer's choice — bind a durable queue to persist messages across restarts, or a transient queue for live-only consumption. Edge Core publishes with `persistent: true` (messages written to disk before broker ACKs).

### Redis

Channel = event `type` (e.g. `edge.node.registered`). Subscribe using `SUBSCRIBE` for exact channels or `PSUBSCRIBE` for wildcard patterns:

```
SUBSCRIBE edge.node.registered       ← exact channel
PSUBSCRIBE edge.node.*               ← all node events
PSUBSCRIBE edge.*                    ← everything
```

**No persistence or replay** — messages are delivered to currently connected subscribers only. If no subscriber is connected when Core publishes, the message is gone. Pick Redis only when consumers are always-on and loss is acceptable.

### MQTT

Topic = event `type` with `.` rewritten to `/` so MQTT segment wildcards (`+`, `#`) work as expected:

| Event type                         | MQTT topic                         |
| ---------------------------------- | ---------------------------------- |
| `edge.node.registered`             | `edge/node/registered`             |
| `edge.node.status_changed`         | `edge/node/status_changed`         |
| `edge.command_execution.completed` | `edge/command_execution/completed` |
| ...                                | ...                                |

Subscription examples:

```
edge/node/+                ← all node events
edge/node/status_changed   ← only status transitions
edge/command_execution/#   ← all command execution events
edge/#                     ← everything
```

Default publish QoS is `1` (at-least-once with broker ACK). Configurable globally via `EVENT_BROKER_MQTT_QOS=0|1|2` — there is no per-event QoS. Consumers should dedup on envelope `id` regardless (multi-admin setups produce duplicate `node.status_changed` events from independent health checkers).

The adapter publishes as MQTT 5 (`proto_ver: :v5` is hardcoded) — MQTT 3.1.1 brokers are not supported.

**Durability is the broker's and consumer's concern.** MQTT QoS controls only the publisher↔broker↔subscriber delivery handshake — it does not make messages durable. Subscribers wanting offline queueing connect with `Session Expiry Interval > 0` on their own connection.

### AWS SNS

Four SNS topics by domain — must be pre-provisioned in your AWS account, ARNs derived from `EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX`:

| Domain                       | Topic name suffix          |
| ---------------------------- | -------------------------- |
| Node + enrollment key events | `edge-nodes-events`        |
| Command execution events     | `edge-commands-events`     |
| Self-update events           | `edge-self-updates-events` |
| SSH events                   | `edge-ssh-events`          |

SNS has no topic-name wildcards. Subscribers filter via _subscription filter policies_ matched against **message attributes**. The adapter promotes two attributes on every publish:

```
type      = "edge.node.status_changed"
corename  = "prod-us"
```

The body remains the full CloudEvents envelope JSON regardless — body and attributes carry the same routing fields, so consumers reading the body don't need to know about attributes.

Filter policy examples:

```json
{"type": [{"prefix": "edge.node."}]}                       // all node events
{"type": ["edge.command_execution.completed"]}             // only completed executions
{"corename": ["prod-us"]}                                  // only this core
{"type": [{"anything-but": "edge.command_execution.expired"}]}  // exclude expired
```

**Durability is the subscriber's concern.** SNS itself doesn't store messages. Subscribers buy durability by being SQS queues (the standard SNS+SQS fan-out pattern), Lambda functions, or HTTPS endpoints with their own retention.

### Google Cloud Pub/Sub

Four Pub/Sub topics by domain — must be pre-provisioned in your GCP project. The adapter constructs full resource names from `EVENT_BROKER_GOOGLE_PUBSUB_PROJECT` (+ optional `EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX`):

| Domain                       | Topic ID                   |
| ---------------------------- | -------------------------- |
| Node + enrollment key events | `edge-nodes-events`        |
| Command execution events     | `edge-commands-events`     |
| Self-update events           | `edge-self-updates-events` |
| SSH events                   | `edge-ssh-events`          |

Pub/Sub has no topic-name wildcards. Subscribers filter via _subscription filter expressions_ matched against **message attributes**. The adapter promotes two attributes on every publish:

```
type      = "edge.node.status_changed"
corename  = "prod-us"
```

The body is the CloudEvents envelope JSON, base64-encoded inside the Pub/Sub `data` field (the wire format requires base64; client libraries auto-decode for subscribers).

Filter expression examples ([Pub/Sub filtering syntax](https://cloud.google.com/pubsub/docs/subscription-message-filter#filtering_syntax)):

```
hasPrefix(attributes.type, "edge.node.")                                      # all node events
attributes.type = "edge.command_execution.completed"                          # only completed executions
attributes.corename = "prod-us"                                               # only this core
NOT (attributes.type = "edge.command_execution.expired")                      # exclude expired
attributes.corename = "prod-us" AND hasPrefix(attributes.type, "edge.node.")
```

Filters are set on subscription creation and **cannot be changed later** — to change a filter, recreate the subscription.

**Durability is built into the subscription.** Pub/Sub buffers messages per subscription (default 7-day retention, max 31) until the subscriber ACKs them. This is closer to SNS+SQS combined than pure SNS — durability is on by default once a subscription exists. If no subscription exists when Edge Core publishes, the message is dropped (same as SNS without subscribers).

---

## Event Types

### Node Events

All node events share the same `data` shape unless noted.

| Type                         | NATS subject / RabbitMQ routing key | Description                                                              |
| ---------------------------- | ----------------------------------- | ------------------------------------------------------------------------ |
| `edge.node.registered`       | `edge.node.registered`              | First-time enrollment — new `node_id` seen for the first time            |
| `edge.node.reregistered`     | `edge.node.reregistered`            | Re-enrollment — existing node came back (reboot, redeploy, etc.)         |
| `edge.node.version_changed`  | `edge.node.version_changed`         | Fires alongside `reregistered` when reported version differs from stored |
| `edge.node.status_changed`   | `edge.node.status_changed`          | Health transition: `healthy` ↔ `unhealthy` ↔ `unreachable`               |
| `edge.node.cluster_changed`  | `edge.node.cluster_changed`         | Node moved to a different cluster                                        |
| `edge.node.update_triggered` | `edge.node.update_triggered`        | Self-update signal successfully sent to this node's Watchtower           |

**Node `data` schema:**

```json
{
  "node_id": "abc-123",
  "cluster_name": "prod",
  "status": "healthy",
  "version": "1.2.0",
  "id_type": "hostname",
  "http_port": 44000,
  "ssh_port": 40022,
  "host_metrics_port": 9100,
  "wireguard_metrics_port": 9101,
  "http_proxy_port": 44001,
  "socks5_proxy_port": 44002,
  "self_update_enabled": true,
  "last_seen_at": "2026-04-14T10:00:00Z",
  "inserted_at": "2026-04-14T09:00:00Z",
  "updated_at": "2026-04-14T10:00:00Z"
}
```

**Extra fields by event type:**

| Event                        | Extra fields                         |
| ---------------------------- | ------------------------------------ |
| `edge.node.status_changed`   | `"previous_status": "healthy"`       |
| `edge.node.version_changed`  | `"previous_version": "1.1.0"`        |
| `edge.node.cluster_changed`  | `"previous_cluster_name": "staging"` |
| `edge.node.update_triggered` | `"self_update_request_id": "<uuid>"` |

**Multi-admin note:** `edge.node.status_changed` may fire from multiple admin instances for the same transition (health check runs on every admin independently). Dedup consumers by `id`.

---

### Command Execution Events

All command execution events share the same `data` shape. `output` is always excluded — fetch via `GET /api/v1/command_executions/:id` if needed.

| Type                               | NATS subject                       | Description                                                               |
| ---------------------------------- | ---------------------------------- | ------------------------------------------------------------------------- |
| `edge.command_execution.created`   | `edge.command_execution.created`   | Execution record created and queued (status: `pending`)                   |
| `edge.command_execution.sent`      | `edge.command_execution.sent`      | Admin delivered execution to agent, agent ACKed (status: `sent`)          |
| `edge.command_execution.completed` | `edge.command_execution.completed` | Agent reported result — `exit_code` populated, consumer decides pass/fail |
| `edge.command_execution.cancelled` | `edge.command_execution.cancelled` | Explicit cancel or agent received SIGTERM (`exit_code: 143`)              |
| `edge.command_execution.expired`   | `edge.command_execution.expired`   | Swept as stale before running (status: `expired`)                         |
| `edge.command_execution.pruned`    | `edge.command_execution.pruned`    | Reaped by background pruning worker — only async deletion path            |

**Command execution `data` schema:**

```json
{
  "command_execution_id": "cmdexec-abc123",
  "command_id": "cmd-xyz789",
  "node_id": "node-abc123",
  "cluster_name": "prod",
  "command_text": "systemctl restart app",
  "timeout": 30000,
  "status": "completed",
  "exit_code": 0,
  "target_all": false,
  "expired_at": null,
  "sent_at": "2026-04-14T10:00:01Z",
  "completed_at": "2026-04-14T10:00:03Z",
  "cancelled_at": null,
  "inserted_at": "2026-04-14T10:00:00Z",
  "updated_at": "2026-04-14T10:00:03Z"
}
```

Notes:

- `timeout` is in milliseconds (e.g. `30000` = 30s)
- `exit_code` is `null` until `completed` or `cancelled`; `143` on SIGTERM cancel
- Null fields are included explicitly as `null`, not omitted
- `output` is never included — unbounded size

**State per event:**

| Event       | `status`             | `exit_code`  | `sent_at`         | `completed_at` | `cancelled_at` |
| ----------- | -------------------- | ------------ | ----------------- | -------------- | -------------- |
| `created`   | `pending`            | `null`       | `null`            | `null`         | `null`         |
| `sent`      | `sent`               | `null`       | populated         | `null`         | `null`         |
| `completed` | `completed`          | integer      | populated         | populated      | `null`         |
| `cancelled` | `cancelled`          | `143` or int | populated or null | `null`         | populated      |
| `expired`   | `expired`            | `null`       | `null`            | `null`         | `null`         |
| `pruned`    | terminal at deletion | as recorded  | as recorded       | as recorded    | as recorded    |

**`pruned` semantics:** fired by the background pruning worker when a finalised execution is deleted from the DB after the retention window. The snapshot reflects the row's terminal state at deletion time (whatever `completed`/`cancelled`/`expired` left it in). `pruned` is the only async deletion path — cascade-from-command-delete is sync and does not fire events.

---

### Self-Update Request Events

| Type                                 | NATS subject / RabbitMQ routing key  | Description                          |
| ------------------------------------ | ------------------------------------ | ------------------------------------ |
| `edge.self_update_request.completed` | `edge.self_update_request.completed` | Batch finished — `summary` populated |

**Self-update request `data` schema:**

```json
{
  "self_update_request_id": "selfupd-abc123",
  "status": "completed",
  "targeting": {
    "type": "clusters",
    "cluster_filters": {},
    "node_filters": { "version": "1.1.*" }
  },
  "summary": {
    "total": 10,
    "triggered": 9,
    "failed": 1
  },
  "inserted_at": "2026-04-14T10:00:00Z",
  "updated_at": "2026-04-14T10:00:05Z"
}
```

Notes:

- `summary` is populated when the batch completes
- `targeting.type` is one of `"all"`, `"nodes"`, `"clusters"`

---

### Enrollment Key Events

| Type                           | NATS subject / RabbitMQ routing key | Description                                                |
| ------------------------------ | ----------------------------------- | ---------------------------------------------------------- |
| `edge.enrollment_key.verified` | `edge.enrollment_key.verified`      | Agent attempted to enroll using a key (success or failure) |

**Enrollment key verified `data` schema:**

```json
{
  "enrollment_key_id": "enrkey-abc123",
  "cluster_name": "prod",
  "name": "prod rollout",
  "uses_remaining": 4,
  "result": "verified",
  "verified_at": "2026-04-14T10:00:00Z"
}
```

Notes:

- `result` is one of `"verified"`, `"invalid_key"`, `"key_expired"`, `"key_spent"`, `"node_limit_reached"`
- On `"invalid_key"` the agent presented a blob that does not match any DB row — `enrollment_key_id`, `cluster_name`, `name`, and `uses_remaining` are all `null`. The event still fires (failed enrollment attempts are real security signal — port scanners, credential stuffing, expired-key rotation surfaces here)
- `name` is an optional human-readable label for the key (display only). `null` when the key was created without one
- The actual key blob is **never** included in the event — it is a credential
- `uses_remaining` reflects state **after** this attempt; for unlimited keys it is `null`

---

### SSH Username Events

| Type                         | NATS subject / RabbitMQ routing key | Description                                                      |
| ---------------------------- | ----------------------------------- | ---------------------------------------------------------------- |
| `edge.ssh_username.verified` | `edge.ssh_username.verified`        | Agent verified an SSH credential against admin (success/failure) |

**SSH username verified `data` schema:**

```json
{
  "ssh_username_id": "sshuser-abc123",
  "node_id": "node-abc123",
  "cluster_name": "prod",
  "username": "deploy",
  "auth_method": "public_key",
  "result": "success",
  "verified_at": "2026-04-14T10:00:00Z"
}
```

Notes:

- `auth_method` is one of `"password"`, `"public_key"`, `"unknown"` (`unknown` when the username doesn't exist for the node — admin can't tell which method the agent attempted)
- `result` is one of `"success"`, `"failure"`
- `username` is what the agent **attempted** — populated even when the username doesn't exist for that node
- When no SSH username row matches the `(node_id, username)` pair, `ssh_username_id` and `cluster_name` are `null`. The event still fires — failed attempts against missing usernames are real SIEM signal (brute-force, credential stuffing patterns)
- Password hashes and public-key strings are **never** included in the event

---

## Schema Principles

- Every event carries a **full object snapshot** in `data` — same fields regardless of event type. Consumers read what they need, ignore the rest.
- Transition events add `previous_*` fields alongside the snapshot — the previous value cannot be derived from the snapshot alone.
- Internal/secret fields never appear: `api_token`, `proxy_password`, `netmaker_host_id`.
- Null fields are always included explicitly as `null`, never omitted.

---

## Semantics

Edge Core publishes accurately regardless of broker. Durability, replay, and retention are the broker's and consumer's responsibility.

- **NATS JetStream / Kafka** — durable append-only log. Consumers can replay from an offset (JetStream consumer position, Kafka consumer group offset). Multiple independent consumers at different positions.
- **NATS pub/sub** — fire-and-forget. Messages are delivered to active subscribers only; missed messages are gone.
- **RabbitMQ** — delivery semantics depend on consumer queue configuration. Durable queue = messages survive broker restart; transient queue = live-only. Core always publishes with `persistent: true`.
- **Redis** — pure pub/sub (`PUBLISH`/`SUBSCRIBE`). No queue, no persistence, no replay. Messages go only to currently connected subscribers. If no subscriber is connected, the message is gone.
- **MQTT** — pub/sub. QoS 0/1/2 governs only the delivery handshake, not durability. The broker itself doesn't retain history (no replay, no consumer offsets). Subscribers wanting offline queueing connect with persistent sessions; subscribers wanting last-message-on-topic semantics rely on broker retained messages (Edge Core does not publish with retain=true).
- **AWS SNS** — fan-out pub/sub. SNS itself stores nothing — once delivered to subscribers (or delivery is exhausted), the message is gone. Durability is the subscriber's responsibility: subscribe an SQS queue for replay (SQS retains up to 14 days), or accept fire-and-forget for Lambda/HTTPS subscribers. SNS retries delivery to its own subscribers on failure (with exponential backoff) but never holds messages for late subscribers.
- **Google Cloud Pub/Sub** — fan-out pub/sub with **per-subscription buffering** built in. Each subscription holds un-ACKed messages for its configured retention (default 7 days, max 31), redelivering until ACKed. Closer to SNS+SQS combined than pure SNS — subscribers get durability for free without standing up a separate queue. If no subscription exists at publish time, the message is dropped (same as SNS without subscribers).

In all cases: each publish is a **full snapshot**, not a diff. If events are missed, the next event is still self-contained.

---

## Spec Files

| File                                                        | Description                                              |
| ----------------------------------------------------------- | -------------------------------------------------------- |
| [`docs/admin-asyncapi-v0.2.0.md`](admin-asyncapi-v0.2.0.md) | This document                                            |
| `docs/admin-asyncapi-v0.2.0.json`                           | AsyncAPI 3.1.0 JSON spec (download from `/api/asyncapi`) |
