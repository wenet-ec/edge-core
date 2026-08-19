# AGENTS.md

This is the canonical repository guide for everyone working in this codebase: maintainers, contributors, reviewers, and coding agents. Read it before making changes; follow local conventions in the affected area as well.

## Project Overview

Edge Core is a distributed edge computing infrastructure management platform built with Elixir and Phoenix. It enables centralized control of geographically distributed edge nodes through two groups of capabilities:

**Functionalities:** remote command execution, SSH backdoor access, metrics aggregation, self-update.
**Connectivity:** cloud↔edge TCP proxying (forward proxy + proxy chaining), edge↔edge WireGuard VPN mesh, edge↔local devices on the same LAN via mDNS.

- **Edge Admin** (cloud server) - Orchestrates nodes, commands, SSH access, proxies, and metrics. PostgreSQL is the production default and the only path that supports multi-admin HA. The same compiled binary also supports SQLite (`DB_ADAPTER=sqlite`) for single-instance hobbyist / homelab deployments — see `examples/README.md` and `examples/lite/`.
- **Edge Agent** (edge nodes) - Standalone binary, primary deployment is one per machine (`network_mode: host`). Also works as a sidecar container on bridge networking. Bundles netclient, SSH server, Prometheus exporters, and forward proxies.
- **Nexmaker** (shared library) - Elixir wrapper for Netmaker API and netclient CLI
- **Netmaker VPN** - WireGuard mesh connecting all components. EMQX/Mosquitto is Netmaker-internal infrastructure only — not used by Edge Admin/Agent application code.

For full architecture detail see `docs/architecture.md`.

## VPN Source Code Reference

**Clone the VPN source code into `./edge_vpn/` when working on VPN behavior.** It is the implementation reference for Netmaker and the forked netclient.

```bash
# Netmaker server (upstream, read-only reference)
git clone --branch v1.6.0 https://github.com/gravitl/netmaker edge_vpn/netmaker

# Netclient (our fork — includes DERP relay integration)
git clone --branch v1.6.0-derp https://github.com/wenet-ec/netclient edge_vpn/netclient
```

When working on anything related to the Netmaker API, netclient enrollment, DERP relay, or WireGuard mesh behavior, read the source directly from `edge_vpn/`. The Netmaker OpenAPI spec is also available at `docs/netmaker-openapi-v1.6.0.yml`.

### DERP and dynamic Settings Config contract

- `CORE_DERP_MAP_URLS` is Edge Admin deployment configuration: an ordered comma-separated list of mirror or hostname-migration URLs for **one complete canonical Core DERP map**. It is not stored in the Admin database.
- Admin's `/start` script bridges `CORE_DERP_MAP_URLS` into netclient's existing `DERP_MAP_URLS` contract before the daemon starts. Do not reuse `DERP_MAP_URLS` as an application configuration name.
- In the `v1.6.0-derp` netclient fork, the first usable `DERP_MAP_URLS` source wins; Core maps are never merged. Every migration URL must serve the same complete map. If no Core source is usable, netclient falls back to Tailscale's public map.
- `ADMIN_URLS` remains a list of independently useful Admin API endpoints; agents use it for transport failover. Do not apply canonical-map semantics to Admin URLs.
- The authenticated agent refresh endpoint is `GET /api/v1/agents/settings/config`. It returns only non-secret Settings Config (`admin_urls`, `core_derp_map_urls`), follows the normal controller/JSON/OpenAPI schema convention, and remains available in degraded mode so agents can recover routes.
- Agent netclient receives a fixed localhost DERP reflection URL at process startup. Dynamic Core map sources are fetched by the Agent application and reflected there; never attempt to change a running netclient's environment.
- The Agent refreshes settings on `REFRESH_SETTINGS_CONFIG_SCHEDULE` (default: every five minutes). Its DERP-map cache refreshes separately through `DERP_MAP_REFRESH_INTERVAL_MS` (default: five minutes).
- Do not introduce an Admin database table, revision counter, or server-side persistence for this Settings Config. Deployment configuration is advertised by each Admin; agents retain learned endpoints locally to tolerate rolling hostname migration.

## Architecture

**Key Architectural Principles:**

1. The database is the only source of truth — admins are stateless compute workers. PostgreSQL is the production default; SQLite is supported as a single-instance alternative selected at runtime via `DB_ADAPTER`. Same compiled binary either way. Multi-admin clustering, HA, and cluster ownership sharding all require PostgreSQL (LISTEN/NOTIFY for cross-admin coordination) — SQLite mode is single-admin only.
2. Admin clustering is masterless peer-to-peer — no strong leader election, no primary/replica. Admins coordinate via Erlang distribution + `:syn` registry within the same admin cluster. A **weak leader** (alphabetically first admin ID in the current topology) is elected deterministically by each admin independently to reduce duplicate work from Quantum — but this is best-effort only, duplicate work is acceptable. See `EdgeAdmin.AdminClustering.Metadata.am_i_weak_leader?/0`. PostgreSQL only.
3. Cluster ownership sharding — exactly one admin owns each edge cluster at a time (one-admin-per-cluster algorithm). The owning Admin runs one `EdgeAdmin.GatewayRegistry.VirtualGateway` per assigned edge cluster, creating an operational hub-and-spoke path for control-plane operations without changing the Agents' direct full-mesh WireGuard topology. HA comes from spinning up additional independent admin clusters sharing the same PostgreSQL database. PostgreSQL only.
4. Agent primary deployment is one-per-machine — `network_mode: host`, privileged. Also works as a sidecar container on bridge networking (see `examples/sidecar/`). Multiple agents on one host is for testing only.
5. Admin↔Agent communication is HTTP over WireGuard VPN, with graceful fallback: raw WireGuard → DERP relay → HTTP polling.
6. Context pattern: Business logic organized in contexts (Commands, Nodes, Vpn, Ssh, etc.)
7. API-first: Both admin and agent expose REST APIs; admin API uses OpenApiSpex for documentation

### Defense-in-depth validation

Edge Core is **strict by default**. Every write to the database passes through 5 layers, each with its own role. Some checks intentionally duplicate across layers — the cost of letting bad input slip one layer deeper is bigger than the cost of running the same check twice.

### Contexts are the domain API

Contexts are the public domain API of each application, not just a foldering convention. REST controllers, MCP tools, workers, schedulers, and other entrypoints should call context functions such as `EdgeAdmin.Nodes.*`, `EdgeAdmin.Commands.*`, `EdgeAdmin.SelfUpdates.*`, and `EdgeAdmin.Events.*` instead of reaching around them into resources, persistence modules, schemas, or checks.

Context functions own the write pipeline: they accept already boundary-shaped input, call the action-specific Form, run DB-backed Checks, call the Resource/Persistence layer, and ensure the Ecto schema changeset and DB constraints remain the final model/backstop layers. If REST and MCP both expose the same operation, both surfaces should converge on the same context function after their own layer-1 validation.

Do not make controllers or MCP tools "smart" by composing forms, checks, repo queries, or schema changesets directly. Do not add snowflake validation in one entrypoint because another layer "probably catches it." Put the rule in the correct layer, then mirror it upward when early rejection improves the API contract.

| Layer | Role | Error code | Where it lives |
| --- | --- | --- | --- |
| 1. **Public-API schema** | Request shape: types, required fields, basic constraints (regex, length, enum). Rejects malformed input at the boundary. | 400 | OpenApiSpex schemas (REST), MCP Peri schemas via Anubis (`EdgeAdminMcp.Tools.*`) |
| 2. **Form module** | Situational rules per action and per role. Composable across actions. Validates external input shape *contextually*. | 422 | `EdgeAdmin.<Domain>.Forms.*` modules, `use EdgeAdmin.Form` |
| 3. **DB checks** | Business rules that need DB state. Composable, distinct from Ecto schema validation. | 422 | `EdgeAdmin.<Domain>.Checks.*` modules (e.g. `NodeLimitBelowCountCheck`, `SubnetOverlapCheck`) |
| 4. **Ecto schema** | Canonical model validation. **Every write passes here, no exception.** Field types, in-record invariants. | 422 | `EdgeAdmin.<Domain>.Schemas.*` changesets |
| 5. **DB constraints** | Final backstop. Only portable invariants that fit both PostgreSQL and SQLite. Unique indexes, not-null, foreign keys, and simple check constraints belong here. SQLite cannot alter constraints after table creation the way PostgreSQL can, so avoid PG-only constraint cleverness unless the feature explicitly drops SQLite support. | varies | Migrations |

**Key implications:**

- **Layer 1 is peer to layer 1.** OpenApiSpex (REST) and MCP Peri (MCP) are both layer-1 gates for their respective surfaces. They should match each other in strictness — drift between them is a real bug, not polish.
- **Layer 1 is *not* peer to layer 2.** Forms are an independent defense layer. Don't collapse layer 1 into layer 2 thinking "the Form catches it anyway" — that removes a defense.
- **MCP does not get to skip the boundary.** MCP tools usually do not have OpenApiSpex, but they still have layer-1 Peri schemas. Keep those schemas as strict as the REST OpenAPI schemas for the same operation, then call the same context API.
- **Controllers and MCP tools are transport adapters.** They translate auth, params, and response shape; they should not own business rules, DB lookups, state transitions, or changeset composition.
- **Adding a new validation rule** usually means adding it to the *layer where it naturally belongs*, then potentially mirroring upward (layer 4 → layer 2 → layer 1) for early rejection. Each layer should be as strict as it can honestly be at its level.
- **Common validators (regex constants, length bounds)** want to be DRY *across surfaces within a layer* — e.g. cluster-name regex shared between OpenApiSpex and MCP Peri — but **not collapsed across layers**.
- **DRY across the boundary surfaces (REST + MCP)** is the live standardization question. See `mcp-parity.md` for the running plan.

## Development Commands

All Elixir/Mix operations use Docker Compose through the `./bin/run` script. No local Elixir/Erlang installation required.

### Docker commands are a deliberate final step, never the default first step

**Do not start work by running `bin/run`.** Start with static inspection and code/documentation edits. Use Docker only when the user explicitly asks you to run it, or after the implementation is complete and container-bound validation is genuinely necessary.

Before every `bin/run` invocation, stop and confirm all of the following:

1. The command is necessary for the task; it is not a reflexive first step.
2. The deployment variant is known.
3. The user has authorized Docker work for this task.

If any point is not true, do not run `bin/run`; continue static work or ask the user. Never run formatting, tests, Compose lifecycle commands, shells, or arbitrary Mix commands automatically. In particular, do not use `bin/run` merely to "see whether things work".

### Source file path headers

Every source file created by an agent must begin with exactly one comment that states its repository-relative path. Use the comment syntax native to the file (`#` for Elixir, `/* ... */` for CSS, `<%!-- ... --%>` for HEEx). Before editing an existing source file, inspect its first lines: retain its existing path header when present, and never add a second, duplicate path comment.

### Tests: read the policy first

**Before creating, changing, or removing any test, read [`TESTING.md`](TESTING.md) in full.** It is the canonical test-scope policy for every Elixir application in this repository. Do not invent coverage from general habits: this repository keeps only fast, deterministic unit tests for pure logic, forms, schemas, checks, filters, views, helpers, and explicit cross-surface contracts. Controllers, plugs that are merely endpoint wiring, MCP tools, workers, supervisors, external IO, and other integration orchestration are verified by the dev/QA staging workflow instead.

### Select the local deployment variant first

**Unless the user explicitly selects Standard/PostgreSQL, the safe default is Lite/SQLite: prefix every Cloud command with `VARIANT=lite`. Never use plain `./bin/run cloud ...` merely because it is the script default. Agent commands have no deployment variant; always run them as `./bin/run edge ...` without `VARIANT`.**

When Docker work is authorized, determine which local deployment the user has started or wants to use:

- **Standard/PostgreSQL** — use `./bin/run …` with no `VARIANT` value. This selects `deploy/local/cloud.yml`.
- **Lite/SQLite** — prefix every **Cloud** `bin/run` invocation with `VARIANT=lite`, for example `VARIANT=lite ./bin/run cloud admin:test`. This selects `deploy/local/cloud.lite.yml`. The Agent has no Lite variant, so use unprefixed Agent commands, for example `./bin/run edge agent:test`.

Use the user's explicit statement as the source of truth. If it is not stated, use Lite when the user has authorized the command; otherwise do not run Docker. A read-only Compose `ps` check is appropriate only when it is needed to resolve an actual conflict with the user's stated variant — do not run it as an automatic preflight.

This choice applies to every **Cloud** `bin/run` operation: service lifecycle, logs, shells, migrations, tests, formatting, linting, quality checks, and arbitrary Mix commands. Agent operations are always unvaried. Mixing default and Lite Cloud commands against the same running setup is incorrect and can target the wrong database or service set.

### Starting Services

```bash
# Start cloud infrastructure (admin + VPN + metrics + DB)
./bin/run cloud up

# Start edge agents (in separate terminal)
./bin/run edge up

# Start everything together
./bin/run all up -d

# Lite/SQLite Cloud plus Agent (the Agent has no variant)
VARIANT=lite ./bin/run cloud up -d
./bin/run edge up -d
```

### Code Quality

```bash
# Format code
./bin/run cloud admin:format
./bin/run edge agent:format
./bin/run all format

# Lint (Credo)
./bin/run cloud admin:lint
./bin/run edge agent:lint

# Quality checks (format + lint + dialyzer)
./bin/run cloud admin:quality
./bin/run edge agent:quality
./bin/run all quality

# Security checks (Sobelow + mix audit)
./bin/run cloud admin:security
./bin/run edge agent:security
./bin/run all security

# Complete check (format, deps, security, lint, dialyzer)
./bin/run cloud admin check
./bin/run edge agent check

# Pre-commit hook (runs check + test)
./bin/run cloud admin precommit
./bin/run edge agent precommit
```

### Database Operations

```bash
# Run migrations
./bin/run cloud db:migrate
./bin/run edge db:migrate

# Reset database (destructive)
./bin/run cloud db:reset
./bin/run edge db:reset

# Setup fresh database
./bin/run cloud db:setup
```

### Development Shell

```bash
# Open IEx shell
./bin/run cloud admin:console

# Open bash shell in running container
./bin/run cloud shell edge_admin
./bin/run edge shell edge_agent

# Execute arbitrary mix command
./bin/run cloud admin <mix-command>
./bin/run edge agent <mix-command>
```

### Logs and Monitoring

```bash
# View logs
./bin/run cloud logs edge_admin
./bin/run edge logs edge_agent
./bin/run all logs

# List running services
./bin/run cloud ps
./bin/run edge ps
```

## Source Of Truth Map

This guide keeps durable rules and contracts. It should not cache module lists, route tables, database tables, background jobs, ports, or step-by-step flows that drift as the code evolves. When you need current behaviour, read the source that owns it.

**Flows and API surfaces**

- Architecture and high-level flows: `docs/architecture.md`.
- Admin REST routes: `edge_admin/lib/edge_admin_web/router.ex`.
- Admin REST controllers/schemas: `edge_admin/lib/edge_admin_web/controllers/`, `edge_admin/lib/edge_admin_web/schemas/`.
- Admin MCP tools: `edge_admin/lib/edge_admin_mcp/tools/`.
- Agent API routes/controllers: `edge_agent/lib/edge_agent_web/router.ex`, `edge_agent/lib/edge_agent_web/controllers/`.
- Agent boot/enrollment: `edge_agent/lib/edge_agent/bootstrap.ex`.
- Command lifecycle: `edge_admin/lib/edge_admin/commands/`, `edge_agent/lib/edge_agent/commands/`.
- SSH flow: `edge_admin/lib/edge_admin/ssh/`, `edge_agent/lib/edge_agent_ssh/`.
- Events/broker/webhooks: `edge_admin/lib/edge_admin/events/`.

**Data, auth, and deployment**

- Database truth is migrations plus schemas: `edge_admin/priv/repo/migrations/`, `edge_admin/lib/edge_admin/**/schemas/`, `edge_agent/priv/repo/migrations/`, `edge_agent/lib/edge_agent/**/schemas/`.
- Runtime DB adapter selection is in `edge_admin/config/runtime.exs` and `edge_admin/lib/edge_admin/repo.ex`.
- Auth headers, token rules, degraded-mode handling, and transport-specific checks live in plugs/controllers/tools. Search `edge_admin/lib/edge_admin_web/plugs/`, `edge_admin/lib/edge_admin_web/controllers/`, and `edge_admin/lib/edge_admin_mcp/tools/`.
- Local and production ports live in Compose/env files, not here: `deploy/local/*.yml`, `deploy/local/.envs/`, `deploy/production/*.yml`, `deploy/production/.envs/`.

### Project Structure

Do not trust a copied tree in this document as a complete source of truth. The repository changes faster than prose. Start each task by inspecting the relevant directory with `rg --files`, `ls`, and nearby modules.

Stable top-level orientation:

- `edge_admin/` — Phoenix Admin server. Domain contexts live under `lib/edge_admin/`; REST/OpenAPI web code lives under `lib/edge_admin_web/`; MCP tools live under `lib/edge_admin_mcp/`; migrations live under `priv/repo/migrations/`.
- `edge_agent/` — Phoenix Agent server. Agent domain code lives under `lib/edge_agent/`; Agent API code lives under `lib/edge_agent_web/`.
- `nexmaker/` — shared Elixir library for Netmaker API and netclient CLI access. Admin and Agent should go through Nexmaker, not call Netmaker/netclient directly.
- `deploy/` — canonical Docker Compose, deployment scripts, and environment files for local and production deployments.
- `examples/` — user-facing deployment examples.
- `docs/` — architecture, generated/static specs, and operator/developer documentation.
- `edge_vpn/` — local source checkout/reference area for Netmaker, netclient, Firezone, and related VPN source. Treat upstream/reference source as read-only unless the task is explicitly about the fork.
- `bin/run` — canonical command harness for Elixir/Mix/Docker workflows.

Within `edge_admin/lib/edge_admin/<domain>/`, prefer the established domain layout when present:

- `<domain>.ex` context module is the public domain API.
- `forms/` is layer-2 input validation and normalization.
- `checks/` is layer-3 DB-backed business validation.
- `schemas/` is Ecto layer-4 model validation.
- `resources/`, `queries/`, `persistence/`, `workflows/`, and `workers/` are internal implementation boundaries; callers outside the domain should usually go through the context.
- `enums/` holds canonical atom/string enum registries shared by schemas and boundary surfaces.

Tests mirror `lib/` only where the test policy allows unit coverage; see `TESTING.md`.

### Background Jobs

Admin and Agent both use Quantum for local periodic work and Oban for durable jobs. Do not maintain worker/job lists here.

- Admin Quantum config: `edge_admin/config/runtime.exs` (`config :edge_admin, EdgeAdmin.BackgroundJobs.Quantum`).
- Admin Quantum implementation/history: `edge_admin/lib/edge_admin/background_jobs/quantum/`.
- Admin Oban runtime config: `edge_admin/config/runtime.exs` (`config :edge_admin, Oban`).
- Admin Oban worker/queue manifest: `edge_admin/lib/edge_admin/background_jobs/oban/queues.ex`.
- Agent Quantum config: `edge_agent/config/runtime.exs` (`config :edge_agent, EdgeAgent.BackgroundJobs.Quantum`).
- Agent Quantum task entrypoints: `edge_agent/lib/edge_agent/background_jobs/quantum/tasks.ex`.
- Agent Oban runtime config: `edge_agent/config/runtime.exs` (`config :edge_agent, Oban`).
- Agent Oban worker/queue manifest: `edge_agent/lib/edge_agent/background_jobs/oban/queues.ex`.

Rule of thumb:

- Quantum is for local periodic jobs that run on every Admin instance.
- Quantum plus the weak-leader guard is for best-effort jobs that should run once per Admin cluster.
- Oban is for jobs that need uniqueness per Core across every Admin node and Admin cluster sharing the same database, or for durable fan-out, retries, and persisted work.

## Configuration

The canonical environment references are the env files themselves, not duplicated lists in this guide. Read the relevant file before changing config behaviour:

- Local env files: `deploy/local/.envs/`
- Production env files: `deploy/production/.envs/`
- Compose wiring: `deploy/local/*.yml`, `deploy/production/*.yml`

**Environment variables:**

The full annotated Admin list lives in `deploy/production/.envs/.edge_admin` — read it directly when you need to know what an Admin variable does. Agent, VPN, DB, broker, and metrics variables live in their own env files beside it. The notes below are only the **non-obvious cross-cutting semantics**, where the variable's behavior is something you can't infer from its name or default:

- `DB_ADAPTER` — `postgres` (default) or `sqlite`. Same compiled binary, runtime-switched. SQLite is single-instance only, no clustering.
- `DB_MIGRATION_LOCK` — `pg_advisory_lock` (default) or `disabled`. `pg_advisory_lock` needs a session-mode Postgres connection — behind PgBouncer transaction pooling, point migrations at the primary directly (same pattern as `DATABASE_NOTIFIER_URL`). `disabled` relies on the migrate sidecar to serialize. Ecto's `:table_lock` default is deliberately not exposed — historically deadlocks on this codebase under heavy DDL even single-admin.
- `ADMIN_DEBUG_DASHBOARD_ENABLED` — exposes the Admin debug surface at `/admin/debug` (default `false`). `ADMIN_DEBUG_AUTH_ENABLED` controls Basic Auth for that dashboard; set it and `ADMIN_DEBUG_DASHBOARD_USERNAME` / `ADMIN_DEBUG_DASHBOARD_PASSWORD` whenever the dashboard is reachable by others.
- `ALL_AUTH_ENABLED` — default authentication setting for REST API, proxy, MCP, metrics, and Admin Debug Dashboard auth. The corresponding specific flag (`API_AUTH_ENABLED`, `PROXY_AUTH_ENABLED`, `MCP_AUTH_ENABLED`, `METRICS_AUTH_ENABLED`, or `ADMIN_DEBUG_AUTH_ENABLED`) overrides it.
- `ENCRYPTION_KEY` / `ENCRYPTION_TAG` — required at boot. Encryption-at-rest for `webhooks.secret` and `webhooks.headers`. If `ENCRYPTION_KEY` is lost, every encrypted row is unrecoverable — back it up alongside `MASTER_KEY`/`SECRET_KEY_BASE`. `ENCRYPTION_TAG` convention: `AES.GCM.V<N>`, bumped on rotation.
- `ROTATE_OLD_ENCRYPTION_KEY` / `ROTATE_OLD_ENCRYPTION_TAG` / `ROTATE_NEW_ENCRYPTION_KEY` / `ROTATE_NEW_ENCRYPTION_TAG` — set all four to trigger rotation via `EdgeAdmin.Release.rotate_encryption_key/0`. Auto-runs on `/start`, also `examples/operations/rotate_encryption_key.yml` for one-off. Idempotent — logs skip if any of the four is missing.
- `EVENT_BROKER_ADAPTER` — `nats`, `kafka`, `amqp091` (alias: `rabbitmq`), `redis`, `mqtt`, `aws_sns`, `google_pubsub`. Endpoint env var is namespaced per adapter — see the `.edge_admin` file for the matrix.
- `CORE_NAME` — identifies this core instance in every event envelope (default: `"default"`). Promoted to message attributes on AWS SNS / Google Pub/Sub for filter policies.
- `EVENT_DELIVERY_MAX_AGE_SECONDS` — cancel broker-publish + webhook-delivery jobs older than N seconds (default `3600`). Checked at `perform/1` start. Set `0` to disable.
- `WEBHOOK_MAX_ATTEMPTS` — total HTTP delivery attempts per event before drop (default `3`). Applied at fan-out time, not configurable per-webhook.
- `WEBHOOK_ALLOW_PRIVATE_IPS` — `true` bypasses the SSRF deny list at create time. Homelab/dev only.
- `PULL_VPN_CONFIG_ENABLED` (agent) — opt out of the daily `netclient pull` backstop.
- `ADMIN_URLS` — ordered, independently usable Admin API URLs. Keep new and old URLs together during a hostname migration so agents can fail over between them.
- `CORE_DERP_MAP_URLS` — ordered URLs for one complete canonical Core DERP map. The first reachable source wins; sources are never merged. During a hostname migration, every listed URL must serve the same complete map.
- `REFRESH_SETTINGS_CONFIG_SCHEDULE` (agent) — cadence for retrieving non-secret `admin_urls` and `core_derp_map_urls` from the authenticated Admin endpoint; defaults to every five minutes.
- `PUSH_DIAGNOSTICS_SCHEDULE` (agent) — diagnostics push cadence; defaults to every two minutes.
- `DERP_MAP_REFRESH_INTERVAL_MS` (agent) — DERP-map cache refresh interval; defaults to five minutes. It is independent of the settings refresh schedule.

Standard auth/host/DB vars (`MASTER_KEY`, scoped keys, `DATABASE_URL`, `NETMAKER_*`, `ENROLLMENT_TOKEN`, `SECRET_KEY_BASE`, `PHX_HOST`) work the way you'd expect — see the env files directly.

## Documentation And Operations

- User-facing guide: `docs/guide.md`.
- Architecture: `docs/architecture.md`.
- Generated/static API specs: `docs/` plus `edge_admin/lib/edge_admin_web/open_api_spec.ex` and `edge_admin/lib/edge_admin_web/async_api_spec.ex`.
- Deployment examples and operations: `examples/`.
- Local and production deployment truth: `deploy/`.

For debugging, inspect the code and env/Compose files first. Run Docker commands only under the Development Commands rules above.
