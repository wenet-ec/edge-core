# Edge Core AsyncAPI — v0.2.0

Event schema reference for all lifecycle events published by Edge Admin.

Interactive viewer: `/asyncdoc` on a running admin. Raw spec: `GET /api/asyncapi`.

---

## Overview

Edge Admin publishes lifecycle events to a configured message broker (NATS JetStream or Kafka/Redpanda). All events follow the [CloudEvents 1.0](https://cloudevents.io) spec. Edge Admin publishes and forgets — it has no knowledge of consumers.

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

| Field             | Description                                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------------------------ |
| `specversion`     | Always `"1.0"`                                                                                                     |
| `id`              | UUID v4 — unique per event, use for consumer-side dedup                                                            |
| `source`          | Always `"https://github.com/wenet-ec/edge-core"`                                                                   |
| `type`            | Event type — matches NATS subject exactly (see tables below)                                                       |
| `time`            | When the state change happened in admin (ISO 8601)                                                                 |
| `datacontenttype` | Always `"application/json"`                                                                                        |
| `corename`        | CloudEvents extension. Identifies the publishing core instance. Set via `CORE_NAME` env var (default: `"default"`) |
| `data`            | Full object snapshot at moment of event (see schemas below)                                                        |

---

## Subjects / Topics

### NATS JetStream

The `type` value is also the NATS subject. Three streams capture all events:

```
Stream: EDGE_NODE_EVENTS          captures: edge.node.>
Stream: EDGE_EXECUTION_EVENTS     captures: edge.execution.>
Stream: EDGE_SELF_UPDATE_EVENTS   captures: edge.self_update.>
```

Subscription examples:

```
edge.node.>              ← all node events
edge.node.status_changed ← only status transitions (server-side filter)
edge.execution.completed ← only completed executions
edge.>                   ← everything
```

### Kafka / Redpanda

Three topics, one per domain:

| Topic                             | Partition key |
| --------------------------------- | ------------- |
| `edge-node-events`                | `node_id`     |
| `edge-command-execution-events`   | `command_id`  |
| `edge-self-update-request-events` | `request_id`  |

Partition key ensures ordering per entity, parallel across entities. Filter by event type using the `type` field in the envelope.

---

## Event Types

### Node Events

All node events share the same `data` shape unless noted.

| Type                         | NATS subject                 | Description                                                              |
| ---------------------------- | ---------------------------- | ------------------------------------------------------------------------ |
| `edge.node.registered`       | `edge.node.registered`       | First-time enrollment — new `node_id` seen for the first time            |
| `edge.node.reregistered`     | `edge.node.reregistered`     | Re-enrollment — existing node came back (reboot, redeploy, etc.)         |
| `edge.node.version_changed`  | `edge.node.version_changed`  | Fires alongside `reregistered` when reported version differs from stored |
| `edge.node.status_changed`   | `edge.node.status_changed`   | Health transition: `healthy` ↔ `unhealthy` ↔ `unreachable`               |
| `edge.node.cluster_changed`  | `edge.node.cluster_changed`  | Node moved to a different cluster                                        |
| `edge.node.update_triggered` | `edge.node.update_triggered` | Self-update signal successfully sent to this node's Watchtower           |
| `edge.node.deleted`          | `edge.node.deleted`          | Node removed from the system                                             |

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

### Execution Events

All execution events share the same `data` shape. `output` is always excluded — fetch via `GET /api/v1/command_executions/:id` if needed.

| Type                       | NATS subject               | Description                                                               |
| -------------------------- | -------------------------- | ------------------------------------------------------------------------- |
| `edge.execution.created`   | `edge.execution.created`   | Execution record created and queued (status: `pending`)                   |
| `edge.execution.sent`      | `edge.execution.sent`      | Admin delivered execution to agent, agent ACKed (status: `sent`)          |
| `edge.execution.completed` | `edge.execution.completed` | Agent reported result — `exit_code` populated, consumer decides pass/fail |
| `edge.execution.cancelled` | `edge.execution.cancelled` | Explicit cancel or agent received SIGTERM (`exit_code: 143`)              |
| `edge.execution.expired`   | `edge.execution.expired`   | Swept as stale before running (status: `expired`)                         |

**Execution `data` schema:**

```json
{
  "execution_id": "exec-abc123",
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

| Event       | `status`    | `exit_code`  | `sent_at`         | `completed_at` | `cancelled_at` |
| ----------- | ----------- | ------------ | ----------------- | -------------- | -------------- |
| `created`   | `pending`   | `null`       | `null`            | `null`         | `null`         |
| `sent`      | `sent`      | `null`       | populated         | `null`         | `null`         |
| `completed` | `completed` | integer      | populated         | populated      | `null`         |
| `cancelled` | `cancelled` | `143` or int | populated or null | `null`         | populated      |
| `expired`   | `expired`   | `null`       | `null`            | `null`         | `null`         |

---

### Self-Update Events

Both events share the same `data` shape.

| Type                         | NATS subject                 | Description                                           |
| ---------------------------- | ---------------------------- | ----------------------------------------------------- |
| `edge.self_update.created`   | `edge.self_update.created`   | Self-update request created with targeting definition |
| `edge.self_update.completed` | `edge.self_update.completed` | Batch finished — `summary` populated                  |

**Self-update `data` schema:**

```json
{
  "request_id": "req-abc123",
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

- `summary` is `null` on `edge.self_update.created` — only populated on `edge.self_update.completed`
- `targeting.type` is one of `"all"`, `"nodes"`, `"clusters"`

---

## Schema Principles

- Every event carries a **full object snapshot** in `data` — same fields regardless of event type. Consumers read what they need, ignore the rest.
- Transition events add `previous_*` fields alongside the snapshot — the previous value cannot be derived from the snapshot alone.
- Internal/secret fields never appear: `api_token`, `proxy_password`, `netmaker_host_id`.
- Null fields are always included explicitly as `null`, never omitted.

---

## Semantics

**Durable append-only log** — not fire-and-forget pub/sub.

- Consumers can replay from an offset (NATS JetStream consumer position, Kafka consumer group offset)
- Multiple independent consumers at different positions
- Each publish is a full snapshot — not a diff. If events are missed, the next event is still self-contained.

---

## Spec Files

| File                                                        | Description                                              |
| ----------------------------------------------------------- | -------------------------------------------------------- |
| [`docs/admin-asyncapi-v0.2.0.md`](admin-asyncapi-v0.2.0.md) | This document                                            |
| `docs/admin-asyncapi-v0.2.0.json`                           | AsyncAPI 3.1.0 JSON spec (download from `/api/asyncapi`) |
