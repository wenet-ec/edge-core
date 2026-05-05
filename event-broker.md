# Event Broker — Design Notes

Captures agreed decisions only.

---

## What This Is

An official extension of Edge Core. Core publishes lifecycle events to a message broker. External consumers subscribe independently. Core publishes and forgets — it has no knowledge of consumers.

Edge Core's responsibility is to publish accurate, well-structured events. Durability, replay, and retention are the broker's and consumer's responsibility — users pick the broker that matches their semantics.

---

## Why

- Eliminates polling from downstream consumers (node sync, deployment status)
- Foundation for notification modules (node down, deployment completed → notify user)
- Not platform-specific — any consumer can subscribe

---

## Event Types

All events fire only for async state changes — sync admin actions (CRUD via API) do not fire events. See [Catalog principle](#catalog-principle) for the full reasoning.

### Node

| Event                        | Description                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------ |
| `edge.node.registered`       | First-time enrollment — new node_id seen for the first time                                |
| `edge.node.reregistered`     | Re-enrollment — existing node_id came back (reboot, redeploy, etc.)                        |
| `edge.node.version_changed`  | Fired alongside `edge.node.reregistered` when reported version differs from stored version |
| `edge.node.status_changed`   | Health transition: `healthy` ↔ `unhealthy` ↔ `unreachable`, any direction                  |
| `edge.node.cluster_changed`  | Node moved to a different cluster                                                          |
| `edge.node.update_triggered` | Admin successfully sent self-update signal to this node's Watchtower                       |

### Command Execution

| Event                              | Description                                                                                                          |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `edge.command_execution.created`   | Execution record created and queued for a node (status: pending)                                                     |
| `edge.command_execution.sent`      | Admin delivered execution to agent, agent ACKed receipt (status: sent)                                               |
| `edge.command_execution.completed` | Agent reported result — carries raw `exit_code`, consumer decides success/failure. `output` excluded (fetch via API) |
| `edge.command_execution.cancelled` | Terminal: explicit cancellation or agent received SIGTERM (exit_code 143)                                            |
| `edge.command_execution.expired`   | Terminal: admin stale sweep or agent detected expiry before running                                                  |
| `edge.command_execution.pruned`    | Background pruning worker reaped an old execution — only async deletion path                                         |

### Self-Update Request

| Event                                | Description                                                   |
| ------------------------------------ | ------------------------------------------------------------- |
| `edge.self_update_request.completed` | Batch finished — carries summary `{total, triggered, failed}` |

### Enrollment Key

| Event                          | Description                                                                                                                                     |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `edge.enrollment_key.verified` | Agent attempted to enroll. Carries `result` (`verified` \| `invalid_key` \| `key_expired` \| `key_spent` \| `node_limit_reached`) — failures included for security audit. |

### SSH Username

| Event                        | Description                                                                                                                                                       |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `edge.ssh_username.verified` | Agent verified an SSH credential against admin. Carries `auth_method` (`password` \| `public_key` \| `unknown`) and `result` (`success` \| `failure`).            |

### Excluded

- **Sync admin CRUD** (cluster / alias / enrollment_key / command / ssh_username / ssh_public_key) — actor already has the response. Deferred to webhook-feature time, demand-driven.
- **Metrics** — pull-based by design.
- **Cascade deletions** — DB-level `on_delete: :delete_all` is silent on the event stream. Cascades happen because of a sync admin action; by the principle, no event.

---

## Subject / Topic Naming

### NATS (`nats` adapter)

Four stream capture prefixes (JetStream only). Streams mirror the code's context boundaries (one stream per `Nodes` / `Commands` / `SelfUpdates` / `Ssh` context):

```
Stream: EDGE_NODES_EVENTS          captures: edge.node.>
Stream: EDGE_COMMANDS_EVENTS       captures: edge.command_execution.>
Stream: EDGE_SELF_UPDATES_EVENTS   captures: edge.self_update_request.>
Stream: EDGE_SSH_EVENTS            captures: edge.ssh_username.>
```

Individual subjects — one per event type. Subjects stay singular per-entity (`edge.node.registered`, not `edge.nodes.registered`); streams are plural containers:

```
edge.node.registered
edge.node.reregistered
edge.node.version_changed
edge.node.status_changed
edge.node.cluster_changed
edge.node.update_triggered

edge.command_execution.created
edge.command_execution.sent
edge.command_execution.completed
edge.command_execution.cancelled
edge.command_execution.expired
edge.command_execution.pruned

edge.self_update_request.completed

edge.enrollment_key.verified
edge.ssh_username.verified
```

Consumer subscription examples:

```
edge.node.>                              ← all node events
edge.node.status_changed                 ← only status changes (server-side filter)
edge.command_execution.completed         ← only completed executions
edge.>                                   ← everything
```

### Kafka / Redpanda

Four topics matching the same domain boundaries:

```
edge-nodes-events
edge-commands-events
edge-self-updates-events
edge-ssh-events
```

Partition keys:

```
edge-nodes-events           → node_id
edge-commands-events        → command_execution_id
edge-self-updates-events    → self_update_request_id
edge-ssh-events             → node_id (verifications partition by the node attempting auth)
```

Consumer filtering by event type is code-level — read `type` from envelope.

### Core Isolation

`core_name` lives in the **event envelope**, not the subject or topic name. Topics/streams are fixed at deploy time. `core_name` as envelope metadata keeps it as data, not routing infrastructure. Broker-level isolation is achieved by pointing each core at its own broker via env vars.

---

## Event Envelope

Every event follows the [CloudEvents 1.0](https://cloudevents.io) spec. `corename` is a CloudEvents extension attribute.

```json
{
  "specversion": "1.0",
  "id": "<uuid v4>",
  "source": "https://github.com/wenet-ec/edge-core",
  "type": "edge.node.registered",
  "time": "2026-04-13T10:00:00Z",
  "datacontenttype": "application/json",
  "corename": "prod-us",
  "data": { ... }
}
```

- `id` — unique per event, use for consumer-side dedup
- `source` — always `"https://github.com/wenet-ec/edge-core"`
- `type` — matches the event names in the tables above; doubles as NATS subject
- `corename` — identifies the publishing core instance. Defaults to `"default"`, set via `CORE_NAME` env var
- `data` — full object snapshot at the moment of the event

Internal/secret fields never appear in any event: `api_token`, `proxy_password`, `netmaker_host_id`.

---

## Event Schemas

### Principle

Every event carries a **full object snapshot** in `data`. Consumers read what they need, ignore the rest.

Exceptions:

- Transition events (`node.status_changed`, `node.version_changed`, `node.cluster_changed`) include `previous_*` fields — previous state cannot be derived from the snapshot alone.
- `execution.completed` excludes `output` — unbounded size, fetch via API.

---

### Node Events

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
  "last_seen_at": "2026-04-13T10:00:00Z",
  "inserted_at": "2026-04-13T10:00:00Z",
  "updated_at": "2026-04-13T10:00:00Z"
}
```

Transition events add previous state fields:

| Event                        | Extra fields             |
| ---------------------------- | ------------------------ |
| `edge.node.status_changed`   | `previous_status`        |
| `edge.node.version_changed`  | `previous_version`       |
| `edge.node.cluster_changed`  | `previous_cluster_name`  |
| `edge.node.update_triggered` | `self_update_request_id` |

`edge.node.version_changed` fires alongside `edge.node.reregistered` when version differs — same re-enrollment, two events.

---

### Command Execution Events

```json
{
  "command_execution_id": "cmdexec-abc123",
  "command_id": "cmd-xyz789",
  "node_id": "node-def456",
  "cluster_name": "prod",
  "command_text": "systemctl restart app",
  "timeout": 30,
  "status": "completed",
  "exit_code": 0,
  "target_all": false,
  "expired_at": null,
  "sent_at": "2026-04-13T10:00:01Z",
  "completed_at": "2026-04-13T10:00:03Z",
  "cancelled_at": null,
  "inserted_at": "2026-04-13T10:00:00Z",
  "updated_at": "2026-04-13T10:00:03Z"
}
```

- `output` excluded from all execution events — fetch via API
- `exit_code` is `null` until `command_execution.completed` or `command_execution.cancelled`
- `command_execution.cancelled` carries `exit_code: 143` (SIGTERM) when cancelled via signal
- Null fields included explicitly as `null`, not omitted

---

### Self-Update Request Events

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
  "inserted_at": "2026-04-13T10:00:00Z",
  "updated_at": "2026-04-13T10:00:05Z"
}
```

- `summary` is populated on `self_update.completed`

---

## Supported Brokers

Broker is opt-in — if `EVENT_BROKER_ENABLED` is not `true`, core runs normally with no event publishing. Each adapter implements two callbacks: `publish(envelope)` and `healthy?()`. Core logic is completely decoupled from the adapter.

| Adapter         | Elixir client      | Status          | Semantics                                                                                                                         |
| --------------- | ------------------ | --------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `nats`          | `gnat`             | **done**        | Pub/sub by default. Set `EVENT_BROKER_NATS_JETSTREAM=true` to enable durable log with replay                                      |
| `kafka`         | `brod`             | **done**        | Durable log, partition ordering. Redpanda is the reference implementation (wire-compatible)                                       |
| `rabbitmq`      | `amqp`             | **done**        | Topic exchange `edge.events`, routing key = event type. Consumer queue durability is the consumer's choice                        |
| `redis`         | `redix`            | **done**        | Fire-and-forget pub/sub. Channel = event type. No durability or replay — pure push to currently connected subscribers             |
| `mqtt`          | `emqtt`            | **done**        | Fire-and-forget pub/sub. QoS 1 publish. Natural fit for IoT/edge users already running EMQX, Mosquitto, HiveMQ                    |
| `aws_sns`       | `ex_aws_sns`       | **done**        | Managed AWS service. Three pre-provisioned topics by domain. Subscribers filter via filter policies on message attributes         |
| `google_pubsub` | `goth` + raw `req` | **in progress** | Managed GCP service. Three pre-provisioned topics by domain. Subscribers filter via subscription filter expressions on attributes |

**Note on broker semantics:** Edge Core publishes accurately regardless of adapter. Durability, replay, and retention are the broker's and consumer's responsibility. Users choose the broker that matches their needs.

**Note on NATS JetStream:** Same binary, same Gnat client, same subjects. JetStream is just a feature enabled on the NATS server. When `EVENT_BROKER_NATS_JETSTREAM=true`, the adapter calls `ensure_streams/0` on startup to auto-create 3 persistent streams. When false, messages are published directly with no persistence — pure pub/sub.

**Note on NATS auth:** Four modes supported, mutually exclusive, token takes precedence: token → username/password → NKey+JWT → NKey only. Token is sufficient for simple/self-hosted deployments. NKey/JWT is for enterprise NATS deployments where operators hand out per-client credentials rather than a shared secret.

**Note on Redpanda:** Wire-compatible with Kafka protocol. brod doesn't distinguish between them.

**Note on Kafka auth:** brod supports SASL plain, SCRAM-SHA-256, and SCRAM-SHA-512 — that's the full set brod implements. No GSSAPI/Kerberos or OAuthBearer. Covers all real-world managed broker scenarios (Confluent Cloud, Aiven, Redpanda Cloud, Upstash, **Azure Event Hubs**).

**Note on Azure Event Hubs:** Event Hubs exposes a Kafka-compatible endpoint at `<namespace>.servicebus.windows.net:9093` and is Microsoft's recommended integration path for Kafka-native applications. Use the `kafka` adapter — no separate Azure adapter needed. Auth is SASL_SSL with username `$ConnectionString` and password = the full Event Hubs namespace connection string. Set `EVENT_BROKER_KAFKA_USERNAME=$ConnectionString` + `EVENT_BROKER_KAFKA_PASSWORD=<connection-string>` + `EVENT_BROKER_KAFKA_SSL=true` + `EVENT_BROKER_KAFKA_SASL_MECHANISM=plain`.

**Note on Kafka DNS:** brod uses the advertised hostname from the Kafka metadata response for reconnections. Netmaker rewrites `/etc/resolv.conf` on startup, causing Docker DNS failures. Fix: assign a fixed IP to the broker container and inject it into admin containers via `extra_hosts` — hosts file resolution bypasses DNS entirely.

**Note on RabbitMQ:** Uses a single durable topic exchange `edge.events` (hardcoded — part of the AsyncAPI contract, same as NATS subjects and Kafka topics). Routing key = event type (e.g. `edge.node.registered`). Core publishes with `persistent: true` — messages are written to disk before the broker ACKs. Consumer queue durability is the consumer's choice; bind with any routing key pattern (`edge.node.*`, `edge.#`, etc.). Credentials embedded in the URL: `amqp://user:pass@host:port` — the amqp library parses them natively. TLS via `EVENT_BROKER_RABBITMQ_SSL=true`.

**Note on Redis:** Pure Pub/Sub — `PUBLISH channel payload` where channel = event type (e.g. `edge.node.registered`). Consumers use `SUBSCRIBE` for exact channels or `PSUBSCRIBE edge.*` for wildcard. No queue, no retention: if no subscriber is connected when Core publishes, the message is gone. No consumer-side durability option. This is the simplest adapter — pick it only when downstream consumers are always-on and loss is acceptable. Credentials embedded in the URL: `redis://:password@host:port` (password-only) or `redis://username:password@host:port` (Redis 6+ ACL). TLS via `EVENT_BROKER_REDIS_SSL=true` (use `rediss://` URL for external brokers).

**Note on MQTT:** Uses `emqtt` v1.15+, which relaxed its transitive `cowlib`/`gun` pins to ranges (`~> 2.13` / `~> 2.1`) — earlier versions (≤1.14.8) hard-pinned exact versions and conflicted with `anubis_mcp`. emqtt is sourced from git (`{:emqtt, github: "emqx/emqtt", tag: "1.15.0"}` in mix.exs) rather than Hex so the upstream `rebar.config.script` runs on our compile and honors `BUILD_WITHOUT_QUIC=1` — Hex flattens dynamic deps at publish time and always lists `quicer` (Microsoft's msquic NIF) as non-optional, even though the upstream script would exclude it locally. Setting `BUILD_WITHOUT_QUIC=1` (baked into both admin Dockerfiles) skips the entire msquic compile, which otherwise adds several minutes to first build. The adapter only uses TCP / TCP+TLS, never QUIC, so quicer is dead weight. Works against any MQTT 3.1.1 / 5 broker. Topic = event type with `.` rewritten to `/` (e.g. `edge.node.registered` → `edge/node/registered`) so MQTT segment wildcards work as expected — subscribers can use `edge/#`, `edge/node/+`, etc. Default publish QoS is 1 (at-least-once) — gives broker ACK without the QoS 2 4-step handshake; configurable via `EVENT_BROKER_MQTT_QOS=0|1|2`. Consumers dedup on envelope `id` regardless. Each admin instance generates a unique client ID (`edge_admin-<node>-<unique>`) so multiple admins sharing a broker don't kick each other off. Auth has three mutually exclusive modes: JWT (`EVENT_BROKER_MQTT_JWT`, sent in CONNECT password slot — works with EMQX/HiveMQ JWT auth chains), username/password (`EVENT_BROKER_MQTT_USERNAME`/`PASSWORD`), or anonymous (default). TLS via `EVENT_BROKER_MQTT_SSL=true`; mTLS via `EVENT_BROKER_MQTT_CLIENT_CERT_FILE` + `EVENT_BROKER_MQTT_CLIENT_KEY_FILE` (requires SSL=true). Custom CA pinning via `EVENT_BROKER_MQTT_CACERT_FILE`.

**Note on Azure Event Grid (MQTT broker mode):** Event Grid added native MQTT 3.1.1 / 5 support in 2024, exposing standard MQTT/TLS endpoints. The `mqtt` adapter works against it — point `EVENT_BROKER_MQTT_URL` at the Event Grid namespace's MQTT endpoint, set `EVENT_BROKER_MQTT_SSL=true`, and use the cert-based auth (mTLS via the cert file env vars). Topic conventions are Event Grid's responsibility once messages arrive.

**Note on Azure IoT Hub:** Technically reachable via the `mqtt` adapter, but IoT Hub uses Azure-specific topic conventions (`devices/{device-id}/messages/events/...`) and CONNECT username format. Our `edge/...` topic shape doesn't fit that model — events would land in topics IoT Hub doesn't route. Not recommended; use Event Hubs (Kafka) or Event Grid (MQTT) instead.

**Note on AWS SNS:** Managed AWS service — no on-prem broker, no `EVENT_BROKER_URLS` style endpoint. Three SNS topics by domain (`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`), pre-provisioned in the operator's AWS account; the adapter constructs full ARNs from `EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX`. SNS has no topic-name wildcards — subscribers filter via _subscription filter policies_ matched against **message attributes**. The adapter promotes `type` and `corename` to attributes on every publish so policies like `{"type": [{"prefix": "edge.node."}]}` work without parsing the body. Body remains the full CloudEvents envelope. Auth uses the standard AWS credential chain (env vars / shared file / EC2 instance profile / EKS IRSA) — resolved by `ex_aws`, no adapter-specific auth env vars. SNS itself stores nothing; durability is the subscriber's responsibility (typically SQS, retains up to 14 days). Local dev / CI runs against [LocalStack](https://localstack.cloud) (`community-archive` tag — `latest` is now Pro-only) by setting `EVENT_BROKER_AWS_SNS_ENDPOINT_URL`; production must leave that var unset. HTTP client is `req` (configured via `config :ex_aws, :http_client, ExAws.Request.Req` in runtime.exs); response XML is parsed by `sweet_xml` which must be a direct dep because ex_aws lists it as `optional: true`.

**Note on Google Cloud Pub/Sub:** Managed GCP service. Same shape as AWS SNS: three pre-provisioned topics by domain (`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`), operator creates them ahead of time, the adapter constructs the full resource name from `EVENT_BROKER_GOOGLE_PUBSUB_PROJECT` (+ optional `EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX` for multiple cores per project). Pub/Sub has no topic-name wildcards either — subscribers filter via **subscription filter expressions** matched against `attributes`; the adapter promotes `type` and `corename` to attributes on every publish so filters like `hasPrefix(attributes.type, "edge.node.")` work without parsing the body. Body is the CloudEvents envelope JSON, base64-encoded inside the Pub/Sub `data` field (the wire format requires base64). Auth is the standard GCP credential chain via `goth`: `GOOGLE_APPLICATION_CREDENTIALS` for service-account JSON (self-hosted), Workload Identity for GKE, GCE metadata server for VMs — no adapter-specific auth env vars. Pub/Sub does buffer per subscription (default 7-day retention, max 31), so durability is more like SNS+SQS combined than pure SNS. HTTP client is **raw `req` against the v1 REST API** — we deliberately skip the auto-generated `google_api_pub_sub` client (which is Tesla-bound and adds a parallel HTTP stack) since the publish surface is a single endpoint. Goth's HTTP layer is also pluggable — a small `Goth.HTTPClient` shim routes its token-refresh calls through `req` too, keeping the codebase Req-native end-to-end.

**Note on Pub/Sub emulator (local dev / CI):** Image: `gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators` (Java 21 + gcloud preinstalled, ~1.17 GB, both amd64+arm64). Started with `gcloud beta emulators pubsub start --host-port=0.0.0.0:8085 --data-dir=/data` — the **default bind is `[::1]:8085`** (IPv6 loopback) which is unreachable from outside the container, so `0.0.0.0` override is mandatory. `--data-dir` persists topic/subscription **definitions** across restarts; published messages are not durable across restarts in any documented way (lifetime = emulator session). The emulator has **no IAM enforcement** and accepts any project ID — we use `edge-local`. Despite Google's docs claiming gRPC-only, the emulator **also serves the standard REST API** on the same port — verified directly. This is what makes Path A (raw Req publishing) work cleanly against both real GCP and the emulator with zero protocol switching. Provisioning runs through a one-shot init container that hits the REST API directly via curl: `gcloud pubsub topics create` is unreliable against the emulator (it tries to authenticate against real GCP for create/delete operations even with `PUBSUB_EMULATOR_HOST` set; only describe/list reliably route to the emulator). Healthcheck is `curl -fs http://127.0.0.1:8085/` returning 200 — the commonly-recommended `cat </dev/tcp/...` TCP probe hangs because cat blocks waiting for response bytes. The image has curl preinstalled but no nc.

---

## Env Vars

```
EVENT_BROKER_ENABLED=true|false
EVENT_BROKER_ADAPTER=nats|kafka|rabbitmq|redis|mqtt|aws_sns|google_pubsub
CORE_NAME=                                     # included in every envelope, defaults to "default"
EVENT_DELIVERY_MAX_AGE_SECONDS=3600            # cancel publish jobs older than N seconds; 0 disables; default 3600

# Endpoint env var is namespaced per adapter:
#   _URLS  (plural)   — adapter accepts a cluster list (NATS, Kafka)
#   _URL   (singular) — adapter takes a single endpoint (RabbitMQ, Redis, MQTT)

# NATS only:
EVENT_BROKER_NATS_URLS=                        # comma-separated cluster, e.g. nats://host:port (use tls:// for external)
EVENT_BROKER_NATS_JETSTREAM=true|false         # default false — enable JetStream durable log
# Auth — pick one, mutually exclusive (token takes precedence):
EVENT_BROKER_NATS_TOKEN=                       # shared token (simple/self-hosted deployments)
EVENT_BROKER_NATS_USERNAME=                    # username + password
EVENT_BROKER_NATS_PASSWORD=
EVENT_BROKER_NATS_NKEY_SEED=                  # NKey seed — standalone or paired with JWT
EVENT_BROKER_NATS_JWT=                         # JWT credential — used alongside NKEY_SEED

# Kafka only:
EVENT_BROKER_KAFKA_URLS=                       # comma-separated host:port cluster list (no scheme)
EVENT_BROKER_KAFKA_USERNAME=                   # optional, omit if no auth
EVENT_BROKER_KAFKA_PASSWORD=
EVENT_BROKER_KAFKA_SASL_MECHANISM=plain        # plain (default) | scram_sha_256 | scram_sha_512
EVENT_BROKER_KAFKA_SSL=true                    # enable TLS — required for public/external brokers

# RabbitMQ only:
EVENT_BROKER_RABBITMQ_URL=                     # single AMQP URL, e.g. amqp://user:pass@host:port[/vhost]
EVENT_BROKER_RABBITMQ_SSL=true                 # enable TLS — required for public/external brokers (CloudAMQP, etc.)

# Redis only:
EVENT_BROKER_REDIS_URL=                        # single URL, e.g. redis://host:port (use rediss:// for TLS)
EVENT_BROKER_REDIS_SSL=true                    # enable TLS — required for public/external brokers (Redis Cloud, Upstash, etc.)

# MQTT only:
EVENT_BROKER_MQTT_URL=                         # single host:port (no scheme)
EVENT_BROKER_MQTT_QOS=1                        # 0|1|2, default 1 (at-least-once with broker ACK)
# Auth — pick one mode (mutually exclusive, JWT precedence):
EVENT_BROKER_MQTT_JWT=                         # JWT bearer token, sent in CONNECT password slot
EVENT_BROKER_MQTT_USERNAME=                    # plain credentials
EVENT_BROKER_MQTT_PASSWORD=
# TLS:
EVENT_BROKER_MQTT_SSL=true                     # enable TLS — required for public/external brokers (HiveMQ Cloud, etc.)
EVENT_BROKER_MQTT_CACERT_FILE=                 # custom CA bundle / pinning
EVENT_BROKER_MQTT_CLIENT_CERT_FILE=            # mTLS — requires SSL=true
EVENT_BROKER_MQTT_CLIENT_KEY_FILE=             # mTLS — requires SSL=true

# AWS SNS only — managed service, no broker URL:
EVENT_BROKER_AWS_SNS_REGION=us-east-1          # required
EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX=arn:aws:sns:us-east-1:123456789012:   # required, includes trailing colon
EVENT_BROKER_AWS_SNS_ENDPOINT_URL=             # leave UNSET in production; only set for LocalStack / CI
# Auth — standard AWS credential chain (resolved by ex_aws, no adapter-specific env vars):
AWS_ACCESS_KEY_ID=                             # env vars, shared credentials file, instance profile, or EKS IRSA
AWS_SECRET_ACCESS_KEY=
AWS_SESSION_TOKEN=                             # optional, when assuming an IAM role via STS

# Google Pub/Sub only — managed service, no broker URL:
EVENT_BROKER_GOOGLE_PUBSUB_PROJECT=            # required, GCP project ID
EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX=    # optional, prepended to topic IDs when sharing one project across multiple cores
EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST=      # leave UNSET in production; host:port (no scheme) for the official Pub/Sub emulator only
# Auth — standard GCP credential chain (resolved by goth, no adapter-specific env vars):
GOOGLE_APPLICATION_CREDENTIALS=                # path to service-account JSON; or unset to use Workload Identity / metadata server
```

Endpoint env var summary — name carries the shape (plural `_URLS` = cluster list, singular `_URL` = single endpoint):

- **NATS** — `EVENT_BROKER_NATS_URLS=nats://host:port` (comma-separated for cluster). Use `tls://` for external/public brokers.
- **Kafka** — `EVENT_BROKER_KAFKA_URLS=host:port` (comma-separated for cluster). No scheme.
- **RabbitMQ** — `EVENT_BROKER_RABBITMQ_URL=amqp://host:port` or `amqp://user:pass@host:port/vhost`. Single URL only — clustering is broker-side. Use `amqps://` for TLS.
- **Redis** — `EVENT_BROKER_REDIS_URL=redis://host:port` or `redis://:password@host:port`. Single URL only. Use `rediss://` for TLS.
- **MQTT** — `host:port` (no scheme). Single URL only — MQTT clients connect to one broker at a time, even when the broker is clustered. Use port `8883` (or whatever the broker exposes for TLS) when `EVENT_BROKER_MQTT_SSL=true`. Topic-per-event uses `/`-separated form (`edge/node/registered`) so MQTT wildcards work.
- **AWS SNS** — no endpoint env var. Region + topic ARN prefix instead. The SNS endpoint (`sns.<region>.amazonaws.com`) is implied; override only via `EVENT_BROKER_AWS_SNS_ENDPOINT_URL` for LocalStack-style emulators in test/staging.
- **Google Pub/Sub** — no endpoint env var. GCP project ID + optional topic-ID prefix. The Pub/Sub endpoint (`pubsub.googleapis.com`) is implied; override only via `EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST` (host:port, no scheme) for the official Pub/Sub emulator in test/staging. Auth resolves via goth's standard chain — `GOOGLE_APPLICATION_CREDENTIALS` for a service-account JSON, or unset to use Workload Identity / GCE metadata server.

---

## Mix Dependencies

All broker client libraries are included in `edge_admin/mix.exs`:

```elixir
{:gnat, "~> 1.13"},    # NATS
{:brod, "~> 3.16"},    # Kafka / Redpanda
{:amqp, "~> 4.1"},     # RabbitMQ
{:redix, "~> 1.5"},    # Redis
{:emqtt, "~> 1.15"},   # MQTT
{:ex_aws, "~> 2.6"},   # AWS SNS — base AWS client (Sigv4, request signing, credential chain)
{:ex_aws_sns, "~> 2.3"}, # AWS SNS — service module (Publish, ListTopics, etc.)
{:sweet_xml, "~> 0.7"},  # required by ex_aws to parse SNS XML responses; ex_aws lists it as `optional: true` so consumers must declare it directly
```

Source is cloned into `./event_broker_libs/` for reading during implementation — do not commit.

---

## Delivery Architecture

Business logic calls `Events.publish/1` immediately after the DB write. `Events` builds the CloudEvents envelope (capturing state at call time) and fans out to every configured delivery channel — today that's `Events.Broker`, which inserts an Oban job into the `event_broker` queue. The worker picks it up asynchronously and calls `Events.Broker.publish_envelope/1` → adapter. Broker health is invisible to the hot path.

Ordering is best-effort — Oban workers compete and retries can reorder. The `time` field on the envelope captures when the event occurred; consumers use it for ordering. Consumers must dedup by `id` regardless (multi-admin setup already produces duplicate `node.status_changed` events from independent health checkers).

**Publish TTL.** `PublishEventWorker.perform/1` checks `Oban.Job.inserted_at` against `EVENT_DELIVERY_MAX_AGE_SECONDS` (default 3600) at the start of each attempt. If the job has been queued longer than the TTL it returns `{:cancel, {:expired, ...}}` — Oban marks the job `cancelled` with the reason in `oban_jobs.errors`, no retry. This caps producer-side resource usage when the broker is unreachable for hours; consumers can still tell stale events from the envelope `time` field if they ever receive them, but the worker stops retrying delivery indefinitely. Set the env var to `0` to disable and rely solely on `max_attempts` for retry exhaustion. The worker's `max_attempts` is `6`, which (with Oban's default exponential backoff) caps total retry time at roughly the same hour the TTL allows — the two limits agree by design.

**Oban queue config** (low concurrency intentional — at 60+ admins sharing one PostgreSQL, each slot is a DB connection):

```elixir
queues: [
  execution_creation: 2,
  cluster_reconciliation: 1,
  self_updates: 1,
  event_broker: 2
]
```

---

## AsyncAPI Spec

```
GET /api/asyncapi   — AsyncAPI 3.1.0 JSON (API key protected)
GET /asyncdoc       — AsyncAPI React viewer (public, fetches spec client-side)
```

- 14 channels, 14 operations, 14 message components — one per event type
- Schema components: `Envelope` + per-domain data schemas
- Servers block documents supported brokers — grows as new adapters are added
- Event type naming: dots separate hierarchy levels, underscores separate words within a level (`edge.node.status_changed`) — CloudEvents spec-compliant

**Note on `/asyncdoc`:** Uses a `MutationObserver` on the `#asyncapi` container to hide the loading spinner — fires when the AsyncAPI component inserts its first element after the async spec fetch completes.

---

## Source Layout

```
edge_admin/lib/edge_admin/events/
├── events.ex                      — public publish API: publish/1; builds the CloudEvents envelope and fans out to every channel
├── catalog.ex                     — 14 typed event structs + event_type/1 + to_data/1
└── broker/
    ├── broker.ex                  — broker delivery channel: enqueue/1 (called by Events.publish/1), publish_envelope/1 (called by the Oban worker), healthy?/0
    ├── adapter.ex                 — @callback publish(envelope) + healthy?()
    ├── supervisor.ex              — starts connection + adapter GenServer, gated on enabled
    ├── adapters/
    │   ├── nats.ex                — Gnat.ConnectionSupervisor + Gnat.pub/3; ensure_streams/0 when JETSTREAM=true
    │   ├── kafka.ex               — brod client + per-topic producers, :hash partitioner
    │   ├── rabbitmq.ex            — amqp, durable topic exchange, routing key = envelope type, auto-reconnect on DOWN
    │   ├── redis.ex               — redix PUBLISH, channel = envelope type
    │   ├── mqtt.ex                — emqtt PUBLISH, QoS 1, topic = envelope type
    │   ├── aws_sns.ex             — ex_aws_sns Publish, three domain topics, type/corename promoted to message attributes
    │   └── google_pubsub.ex       — goth + raw req against the v1 REST API; three domain topics, type/corename promoted to message attributes
    └── workers/
        └── publish_event_worker.ex — Oban worker, queue: event_broker, max_attempts: 6, drops jobs older than EVENT_DELIVERY_MAX_AGE_SECONDS via {:cancel, ...}

event_broker_libs/                 — broker / job-queue source, cloned for reference, not committed
├── nats.ex/                       — gnat (NATS Elixir client)
├── brod/                          — brod (Kafka Erlang client)
├── amqp/                          — amqp (RabbitMQ Elixir client)
├── emqtt/                         — emqtt (MQTT Erlang client, from EMQX team)
├── emqx/                          — EMQX broker source; `apps/emqx_bridge_http` + `apps/emqx_resource` are the relevant subtrees when reading their HTTP delivery patterns (retry classification, SSRF guard, secret wrapping)
├── redix/                         — redix (Redis Elixir client)
├── ex_aws/                        — ex_aws (base AWS client; Sigv4, request signing, credential chain)
├── ex_aws_sns/                    — ex_aws_sns (SNS service module)
├── sweet_xml/                     — sweet_xml (XML parser; required peer dep for SNS responses)
├── cloak/                         — cloak (encryption-at-rest base lib for `secret` + `headers` columns)
├── cloak_ecto/                    — cloak_ecto (Ecto types: `Cloak.Ecto.Binary`, `Cloak.Ecto.Map`, etc.)
├── oban/                          — Oban (job queue used by `PublishEventWorker`); reference when reasoning about retry/cancel/snooze semantics and `%Oban.Job{}` field shape
├── localstack/                    — LocalStack source (reference only — not committed; `community-archive` image is the last free build, `latest` is Pro-only)
└── spec/                          — AsyncAPI spec (reference only)
```

edge_admin/lib/edge_admin_web/
├── open_api_spec.ex — OpenAPI 3.0 document
├── async_api_spec.ex — AsyncAPI 3.1.0 document
└── controllers/async_api/
├── spec_controller.ex — GET /api/asyncapi
└── doc_controller.ex — GET /asyncdoc

````

---

## Known Behaviors

- **`node.status_changed` fires on every admin that owns the node** — `check_node_health/0` runs on every admin instance independently (no weak-leader guard). In a multi-admin cluster, both admins ping the same node and both fire the event on transition. Each gets a unique `id` — consumers dedup via `id`. Not worth fixing on the producer side.
- **`execution.sent` has two publish sites** — `deliver_executions_to_node/2` (admin-push path) and `acknowledge_execution/2` (HTTP polling fallback). The two paths are mutually exclusive per execution, no double-fire risk.
- **`node.version_changed` fires alongside `node.reregistered`** — same re-enrollment produces two events when version differs.

---

## Deployment

Broker services live inside `cloud.yml` and `cloud.test.yml` — they start with the rest of the stack. No separate compose file needed for local/test.

### Local (`deploy/local/cloud.yml`)

```bash
./bin/run cloud start
````

- `edge_event_broker_nats` — NATS (JetStream enabled in server config). Fixed IP `172.20.0.110`. Ports: `44222` (client), `48222` (monitoring)
- `edge_event_broker_nats_ui` — NUI web UI at `41311`
- `edge_event_broker_kafka` — Redpanda. Fixed IP `172.20.0.111`. Port `49092`
- `edge_event_broker_kafka_ui` — Redpanda Console at `49080`
- `edge_event_broker_rabbitmq` — RabbitMQ. Fixed IP `172.20.0.112`. Ports: `45672` (AMQP), `41567` (Management UI), `41569` (Prometheus)
- `edge_event_broker_redis` — Redis. Fixed IP `172.20.0.113`. Port `46379` (client)
- `edge_event_broker_mqtt` — MQTT broker (default image: EMQX 5.x — adapter is broker-agnostic). Fixed IP `172.20.0.114`. Ports: `41883` (MQTT), `48084` (MQTT/WebSocket), `48086` (Dashboard + REST API). Default dashboard creds: `admin`/`public` — change on first login.
- `edge_event_broker_aws_sns` — LocalStack emulator (image: `localstack/localstack:community-archive`). Fixed IP `172.20.0.115`. Port `44566` (LocalStack edge port — all AWS APIs multiplexed). Three SNS topics + matching SQS debug queues are auto-provisioned by `deploy/local/compose/edge_event_broker/aws_sns/init.sh` mounted at `/etc/localstack/init/ready.d/init.sh`. Drain queues with `awslocal sqs receive-message --queue-url ...` to verify publishes — there is no built-in UI.
- `edge_event_broker_google_pubsub` + `edge_event_broker_google_pubsub_init` — Pub/Sub emulator (image: `gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators`). Fixed IP `172.20.0.116`. Port `48087` (gRPC + REST multiplexed). Two services: the emulator itself, plus a one-shot init container that runs `deploy/local/compose/edge_event_broker/google_pubsub/init.sh` once the emulator is healthy. Three topics + three pull debug subscriptions (`{topic}-debug`) are auto-provisioned by hitting the REST API directly with curl. Drain a debug subscription with `curl -X POST -H 'Content-Type: application/json' -d '{"maxMessages":10}' http://127.0.0.1:8085/v1/projects/edge-local/subscriptions/edge-nodes-events-debug:pull` (or run from inside the container). No built-in UI.

All broker services are commented out by default — uncomment whichever adapter you want. All admin containers have all broker IPs in `extra_hosts` to bypass Docker DNS (which netclient breaks by rewriting `/etc/resolv.conf`).

**WSL note:** Redpanda requires `fs.aio-max-nr >= 66543`. Set once: `sudo sysctl -w fs.aio-max-nr=1048576`. Persist: add `fs.aio-max-nr = 1048576` to `/etc/sysctl.d/99-wsl.conf`.

### Production (`deploy/production/cloud.yml` + `event_broker.yml`)

Production `cloud.yml` does not include broker services — use the opt-in `event_broker.yml` overlay:

```bash
docker compose -f deploy/production/cloud.yml -f deploy/production/event_broker.yml up -d
```

### Test (`deploy/production/cloud.test.yml`)

Broker services are included inline (all commented out — uncomment whichever adapter you want):

```bash
docker compose -f deploy/production/cloud.test.yml up -d
```

- NATS + NUI — Fixed IP `172.25.0.110`. Uncomment to use.
- Redpanda + Console — Fixed IP `172.25.0.111`. Uncomment to use.
- RabbitMQ — Fixed IP `172.25.0.112`. Uncomment to use.
- Redis — Fixed IP `172.25.0.113`. Uncomment to use.
- MQTT (EMQX) — Fixed IP `172.25.0.114`. Uncomment to use.
- AWS SNS via LocalStack — Fixed IP `172.25.0.115`. CI/staging only — production must point at real AWS (no service entry, env vars only).
- Google Pub/Sub via emulator — Fixed IP `172.25.0.116`. CI/staging only — production must point at real GCP (no service entry in `event_broker.yml`, env vars only).
- TLS blocks for Redpanda and RabbitMQ documented inline as commented config.

`nats://` for internal Docker network, `tls://` for external/hosted brokers.

### Examples (`examples/event_brokers/`)

Ready-to-use compose files for bring-your-own-broker setups:

```
examples/event_brokers/
├── README.md
├── nats.yml          — NATS (JetStream enabled) + NUI
├── redpanda.yml      — Redpanda + Console
├── kafka.yml         — Apache Kafka KRaft + Kafka UI
├── rabbitmq.yml      — RabbitMQ + Management UI
├── redis.yml         — Redis (fire-and-forget pub/sub, no UI)
├── emqx.yml          — EMQX (MQTT) + built-in dashboard
├── mosquitto.yml     — Mosquitto (MQTT, minimal, no UI)
└── config/
    ├── nats.conf
    ├── nui-context.json
    ├── rabbitmq.conf
    ├── rabbitmq_enabled_plugins
    ├── emqx.conf
    └── mosquitto.conf
```

AWS SNS has no compose file — it's a managed AWS service. The `examples/event_brokers/README.md` has a dedicated section covering topic provisioning, IAM (with IRSA preferred for EKS), subscriber recipes (SQS/Lambda/HTTPS), and filter policy examples.

Usage: `docker compose -f cloud.yml -f ../event_brokers/nats.yml up -d`

---

## Next Steps

For each broker the order is: docker (deploy/local + production) → code + env → examples/k8s/docs.

- `rabbitmq` — **done** (docker + code + env + AsyncAPI + examples + docs)
- `redis` — **done** (docker + code + env + AsyncAPI + examples + k8s Helm values + smoke tested)
- `mqtt` — **done** (docker + code + env + AsyncAPI + examples (EMQX + Mosquitto) + k8s Helm values + smoke tested)
- `aws_sns` — **done** (LocalStack docker for dev/CI + code + env + AsyncAPI + examples doc + k8s Helm values with IRSA-aware secrets + smoke tested with full publish→SQS round-trip)
- `google_pubsub` — **done** (emulator docker for dev/CI + code + env + AsyncAPI + examples doc + k8s Helm values with Workload-Identity-aware secrets + smoke tested with full agent → admin → emulator round-trip via debug pull subscription)

---

## Adapter naming

Most adapters carry the obvious name for what they speak: `nats`, `kafka`, `redis`, `mqtt`, `aws_sns`, `google_pubsub`. The AMQP 0-9-1 adapter started as `rabbitmq` (the dominant deployment of the protocol) but was renamed to `amqp091` once we realized:

- **The protocol is broader than the vendor name implies.** AMQP 0-9-1 is the wire protocol that LavinMQ (CloudAMQP/84codes' Crystal-based broker), AmazonMQ for RabbitMQ, and CloudAMQP all speak. A vendor-named adapter narrows the perceived scope unfairly.
- **It pairs cleanly with future `amqp10`.** The OASIS AMQP 1.0 protocol is unrelated to AMQP 0-9-1 despite the shared name. When the AMQP 1.0 adapter ships (Tier 2 — see Roadmap), having `amqp091` and `amqp10` side-by-side makes the protocol-version distinction immediately visible.
- **`rabbitmq` stays accepted as an alias.** Existing operator configs using `EVENT_BROKER_ADAPTER=rabbitmq` keep working forever — the runtime parser maps both `"amqp091"` and `"rabbitmq"` to the same internal `:rabbitmq` atom. No migration churn.

### What changed

- **Operator-facing primary:** `EVENT_BROKER_ADAPTER=amqp091` (preferred in all docs going forward).
- **Operator-facing alias:** `EVENT_BROKER_ADAPTER=rabbitmq` (continues to work; not deprecated).
- **Internal atom:** `:rabbitmq` (unchanged — supervisor + dispatcher still pattern-match on this).
- **Module + file:** `EdgeAdmin.Events.Broker.Adapters.Rabbitmq` in `lib/.../events/broker/adapters/rabbitmq.ex` (internal naming has no operator value, kept module-name as `Rabbitmq` since RabbitMQ is the protocol's primary deployment).
- **Env var prefix:** `EVENT_BROKER_RABBITMQ_URL` / `EVENT_BROKER_RABBITMQ_SSL` (unchanged — adding parallel aliases doubles the env-parse surface for no operator gain).

### AsyncAPI doc

- Server entry's `title` is `"AMQP 0-9-1 (RabbitMQ-compatible)"`.
- `protocol: "amqp"` paired with `protocolVersion: "0.9.1"` — the spec-endorsed way to disambiguate from AMQP 1.0 (per the AsyncAPI 3.0 Server Object docs, which literally cite `AMQP 0.9.1` as the example value for `protocolVersion`).
- Server identifier _key_ in the `servers` map stays `"rabbitmq"` for AsyncAPI doc continuity. The key is an internal doc identifier, not operator-facing — external consumers parsing the AsyncAPI spec by server key would break if we renamed it.

### What this is NOT

- Not a deprecation of `rabbitmq`. The alias is permanent. We don't intend to ever remove it.
- Not a precedent for renaming other adapters. `aws_sns` and `google_pubsub` stay vendor-named because there's no protocol family they're a synonym for. `kafka` and `mqtt` stay protocol-named because they already are. The renaming applies specifically to AMQP 0-9-1 because it's the one place where the vendor-name vs protocol-name distinction was actually misleading (LavinMQ being a real second-vendor case).

---

## Roadmap

### Cloud-native managed adapters

The default event bus on each major cloud, so users running on that cloud already have one provisioned. Skipping them forces users into heavier alternatives (MSK on AWS, self-managed NATS on GKE) when the native option works fine.

#### `aws_sns` — **shipped**

See [Supported Brokers](#supported-brokers) above and the AWS SNS notes for the full picture. Summary of what shipped:

- Three pre-provisioned SNS topics by domain (`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`).
- `type` and `corename` promoted to message attributes so subscribers can apply filter policies without parsing the body — SNS has no topic-name wildcards.
- Standard AWS credential chain via `ex_aws` (env vars / shared credentials / EC2 instance profile / EKS IRSA).
- LocalStack-based local-dev / CI emulator, with the caveat that LocalStack's free image is now `community-archive` (frozen) — `latest` requires a paid auth token.
- HTTP client routed through `req` (`config :ex_aws, :http_client, ExAws.Request.Req`).

#### `google_pubsub` — **shipped**

See [Supported Brokers](#supported-brokers) above and the Google Cloud Pub/Sub notes for the full picture. Summary of what shipped:

- Pre-provisioned Pub/Sub topics by domain (`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`), names parallel SNS for cross-cloud consistency.
- `type` and `corename` promoted to message attributes so subscribers can apply filter expressions without parsing the body — Pub/Sub has no topic-name wildcards.
- Standard GCP credential chain via `goth` (service-account JSON via `GOOGLE_APPLICATION_CREDENTIALS`, or Workload Identity on GKE / metadata server on GCE — auto-detected).
- Naming locked in across layers: adapter atom `:google_pubsub`, module `EdgeAdmin.Events.Broker.Adapters.GooglePubsub`, env var prefix `EVENT_BROKER_GOOGLE_PUBSUB_*`. AsyncAPI spec uses `googlepubsub` for the `protocol` field and binding key (one word, no underscore — the spec registry's convention).

**Decisions that played out differently than the original plan:**

- **Skipped `google_api_pub_sub`** — kept just `goth`. The auto-generated REST client is Tesla-bound (via `google_gax`), which would have added a parallel HTTP stack alongside our Req-native codebase. Pub/Sub publish is a single endpoint, so we hit `/v1/projects/{project}/topics/{topic}:publish` with raw `Req` directly. End result: ~120-line adapter with `goth` for auth + `Req` for HTTP. Same dep-tree spirit as the SNS adapter (`req` for HTTP, `ex_aws` for SigV4 only).
- **Adapter has no concept of "emulator."** Same shape as SNS where the adapter doesn't know LocalStack exists — emulator handling lives entirely in `runtime.exs`, which sets `base_url` and `auth: :goth | :none` based on whether `EVENT_BROKER_GOOGLE_PUBSUB_EMULATOR_HOST` is set. Adapter just reads two config keys.
- **Emulator REST works.** Despite Google's docs claiming gRPC-only, the emulator also serves the standard REST API on the same port. We verified directly with curl. This is what makes the Path-A (raw Req) decision clean — same code path against real GCP and the emulator, no protocol switching.
- **Provisioning uses curl, not gcloud.** The init container hits the REST API directly: `gcloud pubsub topics create` against the emulator is unreliable (it tries to authenticate against real GCP for create operations even with `PUBSUB_EMULATOR_HOST` set; only describe/list reliably route to the emulator). PUT requests are idempotent so the script is safe across restarts.
- **Healthcheck is curl, not the docs-recommended TCP probe.** `cat </dev/tcp/127.0.0.1/8085` hangs because cat blocks waiting for response bytes the gRPC server never sends. `curl -fs http://127.0.0.1:8085/` returns 200 cleanly once the emulator is accepting connections.
- **k8s Workload Identity is the recommended path.** The Helm chart has a `secrets.googleApplicationCredentialsJson` field for off-GKE deployments; on GKE, leave it blank and bind the ServiceAccount to a GCP service account. The chart auto-mounts the JSON at `/etc/gcp/sa.json` (in a separate Secret to avoid `envFrom` dragging file-shaped keys into env vars).
- **AsyncAPI binding peculiarity.** The `googlepubsub` v0.2.0 binding spec defines no fields for the operation-binding object (it MUST be empty). Pub/Sub-specific routing info lives on the **message binding** instead, where `attributes` is a valid field — that's where we declare the promoted `type` + `corename` attributes. Different shape than SNS, where the operation binding carries `topic`/`consumers`.
- **AsyncAPI 3 oauth2 quirk.** AsyncAPI 3 renamed OpenAPI's `scopes` field to `availableScopes` inside flow objects, and added a top-level `scopes` array on the security scheme itself. Both are required for the validator to accept the `googleOauth2` scheme.

**Code estimate (actual):** ~120 lines for the adapter (smaller than the projected 200, thanks to skipping `google_api_pub_sub`).

#### Azure — already covered, no new adapter needed

Azure has eventing services that route through adapters we already ship:

- **Event Hubs** ✅ — Kafka-compatible endpoint at `<namespace>.servicebus.windows.net:9093`. **Use the existing `kafka` adapter.** Microsoft's recommended path for Kafka-native applications. No new code; just docs (added above in the Kafka note).
- **Event Grid (MQTT broker mode)** ✅ — added MQTT 3.1.1 / 5 support in 2024. **Use the existing `mqtt` adapter** with TLS + mTLS certs.
- **Event Grid (HTTPS push)** ⚠️ — webhook delivery. Will be covered by the future webhook adapter.
- **Service Bus** ❓ — AMQP 1.0, separate from RabbitMQ's 0.9.1. Lib (`amqp10_client` from the RabbitMQ team, MPL-2.0, ~2M downloads) is mature, but Azure positions Service Bus for queues/transactions/sessions and recommends Event Hubs for pub/sub eventing. Tier 2 — build if real demand surfaces.

So Azure shops with eventing needs are **already supported today**, just not advertised. The docs update above adds Event Hubs to the Kafka adapter coverage. No new code needed for the common path.

#### Tier 2 — build if real demand surfaces

- **Apache Pulsar** — real product (CNCF graduate; Yahoo, Tencent, Splunk, Iterable, OVHcloud). Initial audit (Hex/stars/downloads heuristic) flagged a client-tier gap, but reading the source of `emqx/pulsar-client-erl` directly tells a better story: full producer (sync + async + batching) and consumer (Shared/Exclusive/Failover sub types), TLS + mTLS via `enable_ssl: true` + `ssl_opts`, token/JWT auth via `auth_method_name`/`auth_data` on the CONNECT frame, secret censoring in every state struct, `replayq`-backed backpressure with `drop_if_high_mem`, `telemetry` integration. 300+ commits since 2019, actively maintained as of 2025 — engineering work is real (atomicity fixes, OOM handling, OTP 27 compat). Production footprint is non-obvious: the lib powers EMQX Enterprise's Pulsar bridge, so EMQX's ops team finds and fixes real bugs. Not on Hex (vendor as git dep, same pattern as our existing `emqtt` dep). The remaining gap is **OAuth2 client-credentials with token refresh** — necessary for managed Pulsar offerings (StreamNative, DataStax Astra Streaming). Static JWT works today; full OAuth2 needs an upstream PR or external token-refresh process feeding fresh `auth_data` on reconnect. Build if a real user surfaces; ~200 lines for the adapter wrapping the Erlang API.
- **Generic AMQP 1.0 (Solace, ActiveMQ Artemis, IBM MQ, Azure Service Bus)** — `amqp10_client` (RabbitMQ team, MPL-2.0, ~2M Hex downloads, latest 4.2.1 / Nov 2025) is genuinely solid: ~4,200 LoC, real session state machine, active feature work in the rabbitmq-server monorepo (SASL EXTERNAL added Oct 2025, large-message split bug fixed Jul 2025). Tier comparable to `gnat` rather than to git-only libs. URL parser handles `amqp[s]://user:pass@host?sasl=plain&cacertfile=...`. SASL coverage: `ANONYMOUS`, `PLAIN`, `EXTERNAL` (mTLS). **No `XOAUTH2` / bearer-token SASL** — managed brokers needing OAuth2 client-credentials require upstream PR. Azure Service Bus works via SAS-as-PLAIN (`{plain, "<KeyName>", "<KeyValue>"}`) — non-idiomatic but functional. Azure shops with eventing needs already route through Event Hubs (Microsoft's recommended path) via our `kafka` adapter, so Service Bus is a niche secondary path. Build if a user surfaces with a concrete on-prem AMQP-1.0 deployment (Solace, ActiveMQ) or a Service Bus shop that explicitly can't move to Event Hubs. Adapter ~250 lines wrapping the Erlang API; promote `type`/`corename` to AMQP 1.0 application properties (same shape as SNS/Pub/Sub).

#### Won't add

- **AWS EventBridge / Azure Event Grid (HTTPS push)** — HTTPS webhook delivery services, covered by the **webhook adapter** (next-up roadmap item, see below).
- **MQTT 5 enhanced auth** (`custom_auth_callbacks`) — large API surface, almost no real-world demand for our publisher use case (single long-lived connection, auth happens once at startup). JWT-as-password covers OAuth users.

### Catalog principle

**An event fires if and only if the underlying state change is async** — i.e. observable by no party other than through the event.

The sharper framing: events exist for **spontaneous** state changes — things you don't know when to expect, where the only alternative is polling. The async events we ship (node registered, status changed, execution completed, key verified) all share one trait: the consumer cannot predict when they happen, only that they will. Without the event, observation requires a polling loop.

Sync admin actions (CRUD via API) are the opposite. The actor already has the outcome in hand — the response body of their own request. A second consumer wanting that information has alternatives that aren't polling: the API itself, access logs, a dedicated audit log endpoint. Adding events for sync actions duplicates information that's already trivially available, at the cost of catalog noise.

So the rule is: **if you'd otherwise have to poll for it, it deserves an event. If you triggered it yourself, it doesn't.**

Audit-CRUD events stay deferred until a concrete pull-driven audience surfaces — at which point the answer might be events, or might be a `GET /api/v1/audit_log` endpoint, or might be DB triggers. Don't assume the answer is always "more events."

This principle was applied retroactively to the v0 catalog. Two pre-existing events failed it and were dropped; three high-value gaps were identified and added; subjects, streams, and topics were renamed so they mirror the code's context boundaries.

#### Catalog as it stands

**Streams / topics** (one stream per code context, plural names — containers of many events):

| Stream (NATS) | Topic (Kafka / SNS / Pub/Sub) | Captures | Code home |
| --- | --- | --- | --- |
| `EDGE_NODES_EVENTS` | `edge-nodes-events` | `edge.node.>` (room for `edge.cluster.>`, `edge.enrollment_key.>`, `edge.alias.>` when audit-CRUD comes back) | `Nodes` context |
| `EDGE_COMMANDS_EVENTS` | `edge-commands-events` | `edge.command_execution.>` (room for `edge.command.>`) | `Commands` context |
| `EDGE_SELF_UPDATES_EVENTS` | `edge-self-updates-events` | `edge.self_update_request.>` | `SelfUpdates` context |
| `EDGE_SSH_EVENTS` | `edge-ssh-events` | `edge.ssh_username.>` (room for `edge.ssh_public_key.>`) | `Ssh` context |

**Subjects** stay singular per-entity (`edge.cluster.created`, not `edge.nodes.cluster.created`). Underscore-within-level (e.g. `edge.command_execution.*`, `edge.self_update_request.*`) is CloudEvents-spec-compliant: dots separate hierarchy, underscores separate words within a level.

**Wire fields** in event `data` use explicit ID names so subjects, partition keys, and payload fields all line up:

- `command_execution_id` (was `execution_id`)
- `self_update_request_id` (was `request_id`)
- `node_id`, `command_id`, `cluster_name` — unchanged

Kafka partition keys reflect this — execution events partition by `command_execution_id` (was `node_id`, by accident of the partition-key fallback order), giving each execution its own ordered partition lifecycle. Self-update events partition by `self_update_request_id`. Node events still partition by `node_id`.

**Existing events that stay** (5 of the original 7 node events + 5 command_execution events + 1 self-update event):

```
edge.node.registered
edge.node.reregistered
edge.node.version_changed
edge.node.status_changed
edge.node.cluster_changed
edge.node.update_triggered

edge.command_execution.created
edge.command_execution.sent
edge.command_execution.completed
edge.command_execution.cancelled
edge.command_execution.expired

edge.self_update_request.completed
```

**Events dropped** (sync admin actions — failed the principle):

| Event | Reason |
| --- | --- |
| `edge.node.deleted` | Sync admin call. Reconciliation deletes are just the DB catching up to a Netmaker-side decision already made by the sync API path — not an independent async signal. |
| `edge.self_update_request.created` | Sync admin call. The `completed` event carries the request's targeting in its data, so consumers reconstruct the lifecycle from `completed` alone. |

**Events added** (high-value async gaps):

| Event | Why | Fire site |
| --- | --- | --- |
| `edge.enrollment_key.verified` | Agent-driven. Admin learns about enrollment attempts (success and failure) only through this code path. Failed attempts against missing/expired/spent keys are real security signal. | `Nodes.verify_enrollment_key/1` |
| `edge.command_execution.pruned` | Background pruning worker reaps old executions on its own schedule. Consumers maintaining state mirrors have no other way to know. Naming it `pruned` (not `deleted`) is honest — the only async deletion path is pruning; cascade-from-command-delete is sync and doesn't fire. | `Commands.Workers.PruneExecutionsWorker` |
| `edge.ssh_username.verified` | Agent-driven. Same shape as `enrollment_key.verified` — verification decisions for SSH attempts are the only window observers have into auth activity. Carries `auth_method` (`password` \| `public_key` \| `unknown`) and `result` so SIEM consumers can spot brute-force/credential-stuffing patterns. | `Ssh.verify_ssh_credentials/2` |

**Audit-CRUD events deferred** (sync admin actions; revisit when webhooks ship and a concrete user asks for push-based audit):

- `edge.cluster.{created,updated,deleted}`
- `edge.alias.{created,deleted}`
- `edge.enrollment_key.{created,updated,deleted}`
- `edge.command.{created,deleted}`
- `edge.ssh_username.{created,deleted}`
- `edge.ssh_public_key.{created,deleted}`

**Other domains considered and deferred:**

- **Proxy servers** (`edge.proxy.*`). The `proxy_servers/` context is an in-process supervisor for HTTP CONNECT and SOCKS5 tunnels — no DB schemas, no CRUD. The only conceptually event-worthy signal is `proxy.auth_failed` (security audit, same shape as `ssh_username.verified` failures), but auth decisions today are inline in request handlers, not surfaced through a structured context function. Plumbing event publication into the request path is a real change, not a drop-in addition. Tunnel-open / tunnel-close events are volume-killing (every TCP connection — metrics territory, not events). No demand signal. Skip until someone asks.
- **Admin clustering** (`edge.admin.*` — admin joined/left, weak-leader changed, degraded/recovered, cluster ownership shifts). These are real async behaviors with no other observation path, and the platform layer would plausibly subscribe. But: admin topology already has a working internal pub/sub (the `:syn`-based `EdgeAdmin.Admins.Metadata.Events`) for the consumers who actually need it (other admin processes). Prometheus metrics already cover the ops-dashboard use case. And the question "does the broker publish events about Edge Core itself, or only about the things it manages?" is bigger than this catalog round — it broadens the broker's contract from domain events to any-observable-state. Defer until a concrete consumer (likely the platform layer) asks for `edge.admin.*` and we make that scope decision deliberately.

These are not rejected — they are pull-driven future work. The model going forward is: **events are added in response to demand, not speculation.**

#### What is explicitly NOT in the catalog

- **No cascade event firing.** When a command is deleted, its 50 cascaded executions do not fire `command_execution.*` events — DB-level `on_delete: :delete_all` handles the rows, the event stream stays silent for cascade. Same for node→ssh_usernames→ssh_public_keys and node→aliases. Cascades happen because of a sync admin action (deleting the parent), so by the catalog principle they don't deserve events. The "consumer state coherence" concern is theoretical pre-ship; revisit if a real consumer needs it.
- **No `deletion_reason` field.** Dropped along with cascade firing. If audit-CRUD events come back later, `deletion_reason` can be reintroduced then.
- **No `nilify_all` events.** The `node → command_executions` relation is nilify (executions survive node deletion with `node_id` set to NULL). This is a mutation, not a deletion, and we don't have a row-update event shape for executions today. Skip.
- **No metrics-scrape events.** Volume kills this (~290k/day per node), and Prometheus already covers the use case. The original "Metrics — pull-based by design" exclusion holds.
- **No directory restructure** (e.g. `event_broker/` → `events/broker/`). Internal-only, no public-contract impact. The right time is when webhooks ship and `events/webhooks/` becomes a concrete sibling justifying the parent directory.

---

### Webhook feature — shipped

User-configurable HTTP webhook delivery. Same envelope, same event catalog, same `Events.publish/1` call site as the broker; webhook delivery is a parallel channel under the same fan-out. A user can run both at the same time (broker for high-volume internal consumers, webhooks for one-off Slack/SaaS integrations).

Webhooks unlock the long tail of integrations any single broker adapter can't reach — anything that speaks HTTP, including AWS EventBridge / Azure Event Grid (HTTPS push) / Lambda function URLs / Cloud Run / Zapier / Slack / internal services / AI agent receivers — through one feature.

#### Architecture

```
Layer 1 — Events context  (EdgeAdmin.Events)
  • event catalog (EdgeAdmin.Events.Catalog)
  • builds CloudEvents envelopes
  • single function: publish/1

Layer 2 — Delivery channels (parallel, independent)
  • EdgeAdmin.Events.Broker    — to NATS / Kafka / RabbitMQ / Redis / MQTT / SNS / Pub/Sub
  • EdgeAdmin.Events.Webhooks  — to user-configured HTTP endpoints

Layer 3 — Adapters (under each channel)
  • Broker has 7 adapters today
  • Webhook is "one adapter" (HTTP) with N user configs
```

Webhooks share the broker's catalog — anything `Events.publish/1` fires is deliverable. There are no webhook-specific meta-events; observability is terminal logs only.

#### Schema

```elixir
defmodule EdgeAdmin.Events.Webhooks.Schemas.Webhook do
  use EdgeAdmin.Schema

  schema "webhooks" do
    field :url,            :string
    field :secret,         EdgeAdmin.Vault.EncryptedBinary  # HMAC-SHA256 key, Cloak-encrypted at rest
    field :headers,        EdgeAdmin.Vault.EncryptedMap     # static request headers, Cloak-encrypted at rest
    field :event_filters,  {:array, :string}                # wildcard patterns; `*` = any chars
    timestamps()
  end
end
```

Field roles:

- `url` — POST target. Required, validated against SSRF deny list at create time.
- `secret` — HMAC-SHA256 key. Stays server-side; only its derivative `X-Edge-Signature` travels on the wire. Cloak-encrypted, min 32 bytes.
- `headers` — literal HTTP headers on every request (bearer tokens, API keys, etc.). Cloak-encrypted because half the values are credentials.
- `event_filters` — wildcard patterns (`*` matches any sequence of characters, including dots). Same grammar as the rest of the admin API's wildcard filters. Validated at create time against syntax + the live catalog (must match ≥1 known type).

**Webhooks are immutable after create.** Create + delete only. To change anything, delete and recreate. Matches the SSH-username "set once" pattern; trades a small ergonomic cost for a much smaller surface (no update form, no auto-disable / re-enable lifecycle, no pause/resume API, no row-level state machine).

#### Outbound auth

Two independent layers; receivers can use either, both, or neither:

1. **HMAC-SHA256 signature** — server signs the body with the per-webhook `secret`, sends `X-Edge-Signature: sha256=<hex>`. The secret never travels. End-to-end integrity beyond TLS.
2. **HTTP headers** — arbitrary key/value pairs in `headers` are stamped on every request (`Authorization: Bearer ...`, `X-Api-Key: ...`, etc.).

`secret` proves "we sent this exact body"; `headers` carry whatever the receiver's auth policy demands.

#### Wire format

The full CloudEvents envelope is JSON-encoded as the request body with `Content-Type: application/cloudevents+json`. Single shape, no per-webhook configuration. Receivers that want a different shape wrap the webhook with their own translation layer (Lambda, Cloud Function, Worker) — same as Stripe, GitHub, Linear.

#### Delivery semantics

- One Oban job per `(webhook × matched event)` pair. If 3 webhooks match `edge.node.registered`, that's 3 jobs.
- Retry classification:
  - 2xx → `:ok`
  - 408, 429, 503 → `{:error, _}` — Oban retries with exponential backoff
  - Other 4xx / 5xx → `{:cancel, _}` — skip remaining retries
  - Network errors (`econnrefused`, `timeout`, `closed`, `nxdomain`) → `{:error, _}` (recoverable)
- Retry budget comes from `WEBHOOK_MAX_ATTEMPTS` (default 3). Fan-out inserts each Oban job with that value as `max_attempts`. Oban exhausts the budget on recoverable failures, then discards. The worker module's static `max_attempts: 3` is a fallback for direct callers; the fan-out path always sets it explicitly.
- Delivery-age TTL via `EVENT_DELIVERY_MAX_AGE_SECONDS` caps how long a job sits in queue before being cancelled — same pattern as the broker publish worker.
- No row-level state writes on success or failure. Outcomes live in Oban's job table and the application log.

#### Event filtering

Patterns matched against the envelope `type` field. Same wildcard grammar as the rest of the admin API:

- `*` matches any sequence of characters (zero or more, including dots)
- a literal pattern (no `*`) requires exact equality
- `*` alone matches everything

```elixir
["edge.node.registered"]                                # exact
["edge.node.*"]                                         # any node event (also any deeper edge.node.* hierarchy)
["edge.*.completed"]                                    # any "completed" action across domains
["edge.node.registered", "edge.ssh_username.verified"]  # specific list
["edge.node.regis*"]                                    # registered + reregistered
["*"]                                                   # everything
```

Implementation: each pattern compiles to a regex (`*` → `.*`, anchored `\A…\z`). Patterns without a `*` short-circuit to string equality. At 10–100 webhooks per core, regex compilation per call is fine.

Two-level validation at create time:

1. **Syntactic** — non-empty; only `[a-z0-9_.*]`; no leading/trailing dot; no `..`.
2. **Catalog cross-check** — every pattern must match ≥1 event type in `Catalog.all_event_types/0`. Catches typos at API time. `edge.deployment.*` is rejected today (no deployment events exist) and becomes acceptable only when those events ship. The check uses the live catalog, so adding a new event type later automatically widens valid patterns.

Max 20 patterns per webhook. No nested filters, no body-content matching, no JSONPath into `data`.

#### REST API

Create + read + delete only.

- `GET    /api/v1/webhooks` — list
- `POST   /api/v1/webhooks` — create
- `GET    /api/v1/webhooks/:id` — fetch one
- `DELETE /api/v1/webhooks/:id` — remove

Auth via standard `API_KEY` (REST scope) or `MASTER_KEY`.

#### Validation flow

Modeled on the cluster resource — OpenAPI → form → Ecto schema → DB constraint, defense-in-depth at every layer:

- **OpenAPI schemas** — typing, regex, length bounds. `url` `^https?://.+` ≤ 2048; `secret` 32–256; `headers` ≤ 20 entries × ≤ 4096 chars each; `event_filters` 1–20 patterns × ≤ 256 chars each, wildcard `pattern` `^[a-z0-9_*]+(\.[a-z0-9_*]+)*$`. `secret` and `headers` are write-only and never appear in any response. `format: :uri` is **not** used — OpenApiSpex 3.22.2 only validates `:date | :"date-time" | :byte | :uuid | :binary` (verified by reading `lib/open_api_spex/cast/string.ex`); other formats are documentation-only.
- **`CreateWebhookForm`** — SSRF check + filter syntax/catalog cross-check + per-action shape.
- **Ecto schema** — shared model invariant. `validate_required` covers `:url`, `:secret`, `:event_filters`. Cast list is exactly the user-settable surface: `[:url, :secret, :headers, :event_filters]`.

#### Operational decisions

- **Coupling to `EVENT_BROKER_ENABLED`** — webhooks work standalone; many users will want webhooks without standing up a broker.
- **Immutability** — create + delete only; trades ergonomics for a much smaller surface. See [Schema](#schema).
- **Retry budget** — `WEBHOOK_MAX_ATTEMPTS` (default 3) is the only retry-related knob, fleet-wide; passed to Oban at fan-out time as the per-job `max_attempts`.
- **SSRF protection** — private IPs, link-local `169.254.169.254`, RFC1918, and cloud-metadata IPs/hostnames blocked at create time. Opt out via `WEBHOOK_ALLOW_PRIVATE_IPS=true` for homelab/dev. Validation is create-time only — DNS-rebinding defense is the operator's network layer.
- **TLS verification** — default `verify: :verify_peer`. Self-signed support, if added, would be a chart/env-level flag, never per-row.
- **Per-webhook rate limit** — none. Rely on Oban concurrency + receiver-side 429 backpressure (recoverable retry set).
- **Ownership model** — webhooks are core-wide (any admin with `API_KEY` scope can CRUD). Matches the envelope's `corename`.
- **Multi-tenancy** — out of scope for Edge Core itself. The platform layer (Sun) handles tenant scoping above us.

#### What we will NOT build into webhooks (v1)

- **Inbound webhooks** (Edge Admin receiving callbacks from external services) — different feature, different threat model. Skip.
- **Webhook chains / pipelines** — webhook A's response triggers webhook B. Out of scope; users compose this on their side.
- **Body templating / transformation** — receivers want a specific shape that's not our envelope. Out of scope; they wrap our webhook with their own translation layer.
- **Dynamic header templating** — same reason as body templating. Static headers only.
- **Per-row retry / timeout / max-age knobs** — global only: `WEBHOOK_MAX_ATTEMPTS` for retry budget, `Delivery.send/2`'s 10 s timeout, `EVENT_DELIVERY_MAX_AGE_SECONDS` for queue age. Per-row knobs add config surface for hypothetical needs; revisit only if real workloads surface a need.
- **HTTP methods other than POST** — every production webhook system (Stripe, GitHub, Slack, Linear, Shopify, Discord, AWS SNS) uses POST exclusively. PUT/PATCH/GET/DELETE are out.
- **`binary` CloudEvents wire format** — receivers we'd target speak JSON-body webhooks; the binding has near-zero adoption outside Knative/KEDA. Add only if a real CloudEvents-native receiver shows up.
- **JSONPath / body-content filtering** — envelope-field filters only. Users needing more compose their own filter on the receiver side.
- **Webhook discovery / marketplace** — predefined templates for Slack/Discord/etc. Maybe later.

### Operational improvements (orthogonal, lower priority)

- **Outbox pattern** for stronger delivery guarantees. Currently events are enqueued post-DB-write inside `Events.publish/1`. If admin crashes between commit and enqueue, the event is lost. An outbox table (write event row + business row in same transaction, separate worker reads outbox) closes that gap. Real consistency win, adds one DB write per event.
- **Replay / catch-up endpoint**. If a consumer drops offline, on startup they'd want "what events did I miss?" Currently impossible without the broker holding state. A cursor-based REST endpoint (`GET /api/v1/events?since=<timestamp>` returning the same envelope shape) would close this without making the admin an event store.
- **Sidecar consumer reference**. Show users how to build a subscriber. ~50-line Python or Elixir example in `examples/event_brokers/consumers/` would unblock first-time users who otherwise have to read AsyncAPI specs.
- **Event versioning**. We don't currently tag the `data` schema with a version. If we ever change the shape, consumers break silently. Could add `dataschema` field (CloudEvents extension) or version inside `type` (`edge.node.registered.v1`). Cost: small now, expensive later. Worth doing before the first breaking change.
