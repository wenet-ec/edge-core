# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Edge Core is a distributed edge computing infrastructure management platform built with Elixir and Phoenix. It enables centralized control of geographically distributed edge nodes through two groups of capabilities:

**Functionalities:** remote command execution, SSH backdoor access, metrics aggregation, self-update.
**Connectivity:** cloud↔edge TCP proxying (forward proxy + proxy chaining), edge↔edge WireGuard VPN mesh, edge↔local devices (mDNS today; LAN DNS is future scope — see `docs/architecture.md`).

- **Edge Admin** (cloud server) - Orchestrates nodes, commands, SSH access, proxies, and metrics. Runs as multiple peer instances sharing one PostgreSQL database.
- **Edge Agent** (edge nodes) - Standalone binary, primary deployment is one per machine (`network_mode: host`). Also works as a sidecar container on bridge networking. Bundles netclient, SSH server, Prometheus exporters, and forward proxies.
- **Nexmaker** (shared library) - Elixir wrapper for Netmaker API and netclient CLI
- **Netmaker VPN** - WireGuard mesh connecting all components. EMQX/Mosquitto is Netmaker-internal infrastructure only — not used by Edge Admin/Agent application code.

For full architecture detail see `docs/architecture.md`.

## VPN Source Code Reference

**It is strongly recommended to clone the VPN source code into `./edge_vpn/` so AI agents can read the actual implementation instead of hallucinating.**

```bash
# Netmaker server (upstream, read-only reference)
git clone --branch v1.5.1 https://github.com/gravitl/netmaker edge_vpn/netmaker

# Netclient (our fork — includes DERP relay integration)
git clone --branch v1.5.1-derp https://github.com/wenet-ec/netclient edge_vpn/netclient
```

When working on anything related to Netmaker API, netclient enrollment, DERP relay, or WireGuard mesh behavior, read the source directly from `edge_vpn/` rather than guessing. The Netmaker OpenAPI spec is also available at `docs/netmaker-v1.5.1.yml`.

## Architecture

**Key Architectural Principles:**

1. PostgreSQL is the only source of truth — admins are stateless compute workers
2. Admin clustering is masterless peer-to-peer — no strong leader election, no primary/replica. Admins coordinate via Erlang distribution + `:syn` registry within the same admin cluster. A **weak leader** (alphabetically first admin ID in the current topology) is elected deterministically by each admin independently to reduce duplicate work from the LocalScheduler — but this is best-effort only, duplicate work is acceptable. See `EdgeAdmin.Admins.Metadata.am_i_weak_leader?/0`.
3. Cluster ownership sharding — exactly one admin owns each edge cluster at a time (one-admin-per-cluster algorithm). HA comes from spinning up additional independent admin clusters sharing the same PostgreSQL.
4. Agent primary deployment is one-per-machine — `network_mode: host`, privileged. Also works as a sidecar container on bridge networking (see `examples/sidecar/`). Multiple agents on one host is for testing only.
5. Admin↔Agent communication is HTTP over WireGuard VPN, with graceful fallback: raw WireGuard → DERP relay → HTTP polling.
6. Context pattern: Business logic organized in contexts (Commands, Nodes, Vpn, Ssh, etc.)
7. API-first: Both admin and agent expose REST APIs; admin API uses OpenApiSpex for documentation

## Development Commands

All operations use Docker Compose through the `./bin/run` script. No local Elixir/Erlang installation required.

### Starting Services

```bash
# Start cloud infrastructure (admin + VPN + metrics + DB)
./bin/run cloud up

# Start edge agents (in separate terminal)
./bin/run edge up

# Start everything together
./bin/run all up -d
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
./bin/run cloud admin:shell
./bin/run edge agent:shell

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

## Key Interaction Flows

### Node Enrollment

1. Agent starts and runs `EdgeAgent.Bootstrap`
2. Agent determines node identity (hostname, MAC address, etc.)
3. Agent joins VPN using enrollment token: `Nexmaker.EnrollmentKeys.enroll/2`
4. Agent discovers admin URL from Netmaker metadata
5. Agent registers with admin: `POST /api/agents/nodes`
6. Admin returns API token and config
7. Agent registers node aliases (best-effort, from `ALIASES` env var — comma-separated friendly names)
8. Agent downloads pending command executions
9. Agent ready to receive commands

### Command Execution

1. Admin receives command request: `POST /api/commands`
2. `EdgeAdmin.Commands.create_command/1` creates Command record
3. Oban worker creates CommandExecution records per target node
4. Background scheduler identifies healthy nodes (every 10s)
5. Admin sends executions to agents: `POST /api/agents/command_executions`
6. Agent executes via `EdgeAgent.Commands.execute/1`
7. Agent reports results: `PATCH /api/agents/command_executions/:id`
8. Results visible through admin API

### SSH Access

1. User SSH connects to agent port 40022
2. Agent's `EdgeAgent.SshServer` receives connection
3. Agent calls admin to verify credentials: `POST /api/agents/ssh_verifications`
4. Admin checks `ssh_usernames` + `ssh_public_keys` tables
5. Admin returns approval/denial
6. Agent grants/denies SSH access accordingly

## Important Implementation Details

### Database Schemas

**Edge Admin (PostgreSQL):**

- `clusters` - VPN network definitions
- `nodes` - Edge device registrations with health status
- `aliases` - DNS name mappings for nodes
- `enrollment_keys` - VPN enrollment key records
- `commands` - Commands to execute across nodes
- `command_executions` - Per-node execution tracking
- `node_metrics_cache` - Cached metrics for Layer 3 (HTTP polling) mode
- `ssh_usernames` - SSH login credentials
- `ssh_public_keys` - Authorized keys for SSH users
- `self_update_requests` - Container update scheduling
- `oban_jobs` - Background job queue

**Edge Agent (SQLite):**

- `settings` - Key-value configuration store
- `command_executions` - Local execution tracking
- `oban_jobs` - Local background jobs

### Authentication

**Admin API:**

- `MASTER_KEY` header - Full access, fallback for all other keys
- `API_KEY` header - REST API access (clusters, nodes, commands, SSH, enrollment keys)
- `METRICS_KEY` header - Read-only metrics access
- `PROXY_KEY` header - Proxy tunnel access
- `MCP_KEY` header - MCP server access
- Agent API token - Per-agent authentication for status reporting

**Agent API:**

- API token from registration - Admin-to-agent communication

### Project Structure

```
edge_core/
├── edge_admin/          # Phoenix admin server
│   ├── lib/
│   │   ├── edge_admin/          # Business logic contexts
│   │   │   ├── commands/        # Command execution system
│   │   │   ├── nodes/           # Node management
│   │   │   ├── ssh/             # SSH credential management
│   │   │   ├── vpn/             # Netmaker VPN integration
│   │   │   ├── proxy_servers/   # Proxy coordination
│   │   │   ├── metrics/         # Metrics aggregation
│   │   │   └── edge_clusters/   # Cluster management + Erlang peer coordination
│   │   └── edge_admin_web/      # Phoenix web layer
│   │       ├── controllers/     # REST API controllers
│   │       ├── schemas/         # OpenAPI schemas
│   │       └── router.ex        # Route definitions
│   ├── priv/
│   │   └── repo/migrations/     # Database migrations
│   └── test/                    # Test files mirror lib/
├── edge_agent/          # Phoenix agent server
│   ├── lib/
│   │   ├── edge_agent/          # Agent business logic
│   │   │   ├── bootstrap.ex     # Startup and registration
│   │   │   ├── commands/        # Local command execution
│   │   │   ├── ssh_server/      # Embedded SSH server
│   │   │   ├── settings/        # Persistent config (SQLite)
│   │   │   └── edge_clusters/   # Admin discovery and health
│   │   └── edge_agent_web/      # Agent API
│   └── test/
├── nexmaker/            # Shared Netmaker library
│   └── lib/nexmaker/
│       ├── enrollment_keys.ex   # VPN enrollment
│       ├── networks.ex          # Network management
│       ├── hosts.ex             # Host management
│       └── nodes.ex             # Node management
├── edge_vpn/            # Reference VPN source (Go, read-only)
│   ├── netmaker/        # Netmaker server source + swagger.yaml
│   └── netclient/       # Netclient CLI source (our fork adds DERP)
├── deploy/              # Docker Compose configurations
│   ├── local/           # Local development
│   │   ├── cloud.yml    # Admin + infrastructure
│   │   ├── edge.yml     # Agent services
│   │   └── .envs/       # Environment files
│   └── production/      # Production configs
├── examples/            # Deployment examples for users
│   ├── lite/            # Single admin, Mosquitto, no metrics
│   ├── standard/        # 4 admins (2 clusters), EMQX, full metrics
│   ├── sidecar/         # Agent as sidecar container (bridge networking)
│   └── relay/           # Self-hosted DERP relay node
├── docs/                # Architecture docs and API specs
│   ├── architecture.md
│   ├── admin-v0.2.0.json
│   └── netmaker-v1.5.1.yml
└── bin/
    └── run              # Management script
```

### Key Modules

**Edge Admin (`edge_admin/lib/edge_admin/`):**

- `nodes.ex` - Node enrollment, discovery, health monitoring
- `commands.ex` - Command orchestration (detailed in Command Execution flow)
- `ssh.ex` - SSH credential management
- `vpn.ex` - Netmaker API wrapper
- `proxy_servers.ex` - HTTP/SOCKS5 proxy coordination
- `metrics.ex` - Metrics aggregation
- `edge_clusters.ex` - Cluster management and metadata

**Edge Agent (`edge_agent/lib/edge_agent/`):**

- `bootstrap.ex` - Startup orchestration, VPN enrollment, admin discovery, alias registration
- `commands.ex` - Local command execution via System.cmd
- `ssh_server.ex` - Embedded SSH server (port 40022)
- `proxy_servers.ex` - Local HTTP/SOCKS5 proxy servers
- `settings.ex` - Persistent configuration (SQLite key-value store)
- `identity.ex` - Node identity determination (hostname, MAC, etc.)
- `vpn/vpn.ex` - VPN join/health-check operations; `vpn/workers/pull_vpn_config_worker.ex` for periodic pulls
- `lan/mdns.ex` - mDNS advertisement (`{node_id}.local` + `_edgecore._tcp.local` service record)

**Nexmaker (`nexmaker/lib/nexmaker/`):**

Shared path dependency used by both admin and agent. Neither ever calls Netmaker or netclient directly — all interaction goes through Nexmaker.

Two interfaces:

- `Nexmaker.Api.*` — HTTP client (`Req`) for the full Netmaker REST API. Auth via MASTER_KEY bearer token. Modules: `Networks`, `EnrollmentKeys`, `Hosts`, `Nodes`, `DNS`, `Superadmin`, `Gateways.*`, `EMQX`.
- `Nexmaker.Cli` — Wrapper around the `netclient` binary (shelled out via `System.cmd`). Functions: `join_network/1`, `leave_network/1`, `list_networks/0`, `check_connection/1`, `health_check/1`, `pull/0`, `list_peers/1`, `ping_peers/1`.

Config:

```elixir
config :nexmaker,
  base_url: System.get_env("NETMAKER_API_URL"),
  master_key: System.get_env("NETMAKER_MASTER_KEY")
```

### Background Jobs

Admin background work is split between two schedulers with different semantics:

**Quantum LocalScheduler** — runs on every admin instance independently. Jobs that should run cluster-wide use the weak leader guard (`Metadata.am_i_weak_leader?/0`) to reduce duplicate work:

- `EdgeAdmin.Vpn.run_zombie_admin_cleanup/0` - Cleans up orphaned admin entries in Netmaker (weak leader only)
- `EdgeAdmin.Vpn.sync_vpn_config/0` - Periodic `netclient pull` as a VPN consistency backstop (every admin)
- `EdgeAdmin.Admins.Metadata.recompute_now/0` - Recomputes cluster ownership assignments (every admin)
- `EdgeAdmin.Admins.Discovery.scan_and_connect_admins/0` - Discovers and connects to peer admins (every admin)
- `EdgeAdmin.Nodes.check_node_health/0` - Health checks owned nodes (every admin)
- `EdgeAdmin.Commands.deliver_local_executions/0` - Delivers pending commands to agents (every admin)
- `EdgeAdmin.Commands.expire_stale_executions/0` - Sweeps stale command executions (every admin)

**Oban** — jobs inserted by the DB peer leader, competed for by any admin across all clusters sharing the same DB:

- `EdgeAdmin.Commands.Workers.CreateExecutionsWorker` - Creates CommandExecution records for each targeted node
- `EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker` - Enqueues one `ReconcileClusterWorker` job per cluster
- `EdgeAdmin.Nodes.Workers.ReconcileClusterWorker` - Syncs a single cluster's node state with Netmaker VPN
- `EdgeAdmin.SelfUpdates.Workers.TriggerSelfUpdateWorker` - Coordinates container updates

**Agent Workers:**

- `EdgeAgent.Commands.Workers.EnqueueExecutionWorker` - Receives executions from admin
- `EdgeAgent.Commands.Workers.ExecuteCommandWorker` - Executes commands locally
- `EdgeAgent.Commands.Workers.ReportExecutionWorker` - Reports results to admin
- `EdgeAgent.Commands.Workers.SyncUnprocessedExecutionWorker` - Syncs pending executions
- `EdgeAgent.EdgeClusters.Workers.DiscoverAdminWorker` - Discovers admin URL from VPN metadata
- `EdgeAgent.EdgeClusters.Workers.ReportHealthCheckWorker` - Sends health status to admin
- `EdgeAgent.Vpn.Workers.PullVpnConfigWorker` - Periodic VPN config pull (daily, opt-out via `PULL_VPN_CONFIG_ENABLED`)

### Testing Patterns

- Use `EdgeAdmin.Factory` / `EdgeAgent.Factory` (ExMachina) for test data
  - `build/2` for structs, `insert/2` for database records
  - Factories include: nodes, commands, executions, clusters, SSH credentials
- Mock external services (Netmaker API) with `Mox`
  - Define behaviors in test environment
  - Use `expect/4` and `stub/3` for mock expectations
- Database sandboxing via `Ecto.Adapters.SQL.Sandbox`
  - Each test runs in a transaction
  - Use `DataCase` for database tests, `ConnCase` for controller tests
- Test async jobs with `Oban.Testing`
  - Use `perform_job/2` to test worker logic synchronously
  - Verify job enqueueing with `assert_enqueued`
- Test organization: `test/edge_admin/` mirrors `lib/edge_admin/` structure

## Service Endpoints

**Cloud Services:**

- Edge Admin API: http://localhost:44000 (external: 34000, 34001, ...)
- Netmaker UI: http://localhost:48080
- Netmaker API: http://localhost:48081
- EMQX Dashboard: http://localhost:48085
- VictoriaMetrics: http://localhost:48428
- PostgreSQL: localhost:5432

**Edge Services:**

- Edge Agent 1: http://localhost:44000
- Edge Agent 2: http://localhost:44001
- Docker Registry: http://localhost:45000

## Configuration

**Environment variable files (`deploy/local/.envs/`):**

- `.edge_admin` - Edge Admin application config
- `.edge_admin_db` - PostgreSQL database config
- `.edge_admin_test` - Test environment config
- `.edge_agent` - Edge Agent application config
- `.edge_agent_test` - Agent test environment config
- `.edge_vpn` - Netmaker VPN config
- `.edge_vpn_db` - Netmaker database config
- `.edge_vpn_broker` - EMQX message broker config
- `.edge_metrics_storage` - VictoriaMetrics storage config
- `.edge_metrics_collector` - Metrics collector config

Production files follow the same pattern in `deploy/production/.envs/`

**Critical environment variables:**

- `MASTER_KEY` - Full access, fallback for all scoped keys
- `API_KEY` - REST API authentication (scoped; defaults to MASTER_KEY)
- `METRICS_KEY` - Metrics API authentication (read-only; defaults to MASTER_KEY)
- `DB_URL` - PostgreSQL connection string (admin, alternative to individual DB\_\* vars)
- `NETMAKER_*` - Netmaker API credentials, URLs, and tokens
- `ENROLLMENT_TOKEN` - Agent VPN enrollment key
- `SECRET_KEY_BASE` - Phoenix secret for sessions and encryption
- `PHX_HOST` - Public hostname for admin API

## Technology Stack

- **Framework:** Elixir 1.19+, Erlang 28.3+, Phoenix 1.8
- **Databases:** PostgreSQL 18 (admin), SQLite 0.22 (agent), Ecto 3.13
- **VPN:** Netmaker (Go), netclient, WireGuard
- **Jobs:** Oban 2.20, Quantum 3.5
- **Metrics:** Prometheus exporters, VictoriaMetrics, PromEx 1.11
- **HTTP:** Req 0.5, Bandit server
- **API:** OpenApiSpex 3.22 (OpenAPI/Swagger)
- **Auth:** Argon2, JWT-like tokens
- **Testing:** ExUnit, ExMachina, Mox, Faker
- **Quality:** Credo, Dialyxir, Sobelow, Mix Audit

## API Documentation

OpenAPI specs auto-generated and served at:

- `/api/openapi` - OpenAPI JSON
- `/api/swaggerui` - Swagger UI
- `/api/redoc` - ReDoc UI

Major API endpoints documented inline with `@doc` tags and OpenApiSpex schemas.

## Common Development Workflows

### Adding a New Feature

1. Start services: `./bin/run all up -d`
2. Make code changes in `edge_admin/lib/` or `edge_agent/lib/`
3. Create migrations if needed: `./bin/run cloud admin ecto.gen.migration migration_name`
4. Run migrations: `./bin/run cloud db:migrate`
5. Add tests in corresponding `test/` directory
6. Run tests: `./bin/run cloud admin:test` or for specific file
7. Format code: `./bin/run all format`
8. Run quality checks: `./bin/run all quality`

### Debugging

```bash
# Attach to running admin with IEx
./bin/run cloud shell edge_admin
iex -S mix

# View real-time logs
./bin/run cloud logs edge_admin
./bin/run edge logs edge_agent

# Inspect database
./bin/run cloud admin ecto.migrate --log-sql
./bin/run cloud admin dbconsole

# Check Oban jobs
# In IEx: Oban.check_queue(queue: :default)
```

### Troubleshooting

**VPN connectivity issues:**

- Check Netmaker is healthy: `./bin/run cloud logs edge_vpn`
- Verify enrollment token in `.edge_agent` env file
- Check agent VPN status: `./bin/run edge shell edge_agent` then `netclient list`

**Database connection errors:**

- Ensure database is running: `./bin/run cloud ps`
- Reset database: `./bin/run cloud db:reset`
- Check DB_URL or DB_HOST/DB_PORT/DB_NAME in `.edge_admin` env file

**Failed tests:**

- Clean test database: `./bin/run cloud admin ecto.drop` then `./bin/run cloud admin:test`
- Check for async test conflicts (use `async: false` if needed)
- Verify mocks are properly configured in `test/test_helper.exs`
