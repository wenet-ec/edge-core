# Testing Policy

## Overview

Edge Core has two testing tiers, with a clear split of responsibility.

**Unit tests (this repo)** — for both `edge_admin/` and `edge_agent/`, unit
tests cover **pure logic only**: things we can extract out of the codebase
and verify deterministically with inputs and expected outputs.

**System and integration tests** — live outside this repo. Our dev and QA
team verifies system behaviour manually on staging servers, including:

- Real Netmaker / netclient enrollment and mesh formation.
- Cross-admin coordination (Erlang distribution, `:syn`, ETS metadata).
- Cross-cluster routing through Gateway processes.
- HTTP/SOCKS5 proxy paths against real targets.
- SSH backdoor authentication end-to-end.
- Event publishing against real brokers (NATS, Kafka, RabbitMQ, etc.).
- Webhook delivery to real receivers.
- Self-update flows triggered against agent containers.
- Postgres + SQLite parity under both `DB_ADAPTER` settings.

This split is intentional. The unit suite stays fast, deterministic, and
narrow; the integration coverage lives where the integrations actually
run.

## What "pure logic" means

A unit test belongs in this codebase if it satisfies all three:

1. **Contained** — runs in one process, no external services (Netmaker,
   netclient, brokers, real HTTP, real `:gen_tcp`, distributed Erlang).
2. **No mocks** — does not stand up Mox expectations to simulate cross-module
   interactions. (One narrow exception below.)
3. **Deterministic** — exercises a function whose output is determined
   solely by its inputs (or by inputs + database state, when the function's
   job *is* to query the database).

If a test would need to mock `Req`, simulate WireGuard, fake `:syn`, or
intercept Netmaker API calls to be meaningful, it doesn't belong here —
that's integration territory and lives in staging.

## What we DO unit-test

- **Forms** (layer 2 input validation) — every changeset rule.
- **Schemas** (layer 4 model validation) — every changeset rule.
- **Checks** (layer 3 DB-state-dependent rules) — via `EdgeAdmin.DataCase`,
  inserting real rows.
- **Filters** (Ecto query builders) — via `EdgeAdmin.DataCase`, asserting
  which rows the filter selects from a real `Repo.all`.
- **Views** — the canonical map shape REST and MCP both serialize. Pin the
  shape, the field set, and (for security-relevant fields) explicit
  non-leakage.
- **Pure helpers** — anything that takes data and returns data: parsers,
  formatters, normalisers, classifiers, key derivers, hash signers, etc.
- **Cross-surface contracts** — places where REST and MCP must agree
  (changeset error rendering, event catalog, response envelope shape, blocked
  operations under degraded mode). One representative test per shared module.
- **Defense-in-depth boundaries** — when a rule lives at multiple layers
  (layer 2 form + layer 4 schema), each layer is unit-tested independently.

## What we DO NOT unit-test

These get exercised by the QA team on staging instead:

- **Controllers / MCP tools** — thin orchestration around tested upstream
  modules. Wiring fails loudly at the first dev/staging request.
- **JSON renderers** — passthroughs around View + ResponseEnvelope (both
  unit-tested). Same logic.
- **GenServers, Supervisors, DynamicSupervisors** — state machinery, not
  pure logic.
- **HTTP clients, broker adapters, netclient wrappers** — external IO.
- **Oban workers** — orchestration; their inner logic lives in domain
  modules and is unit-tested there.
- **OpenAPI / AsyncAPI schemas** — declarative documentation, schema-as-
  source-of-truth.
- **Macros and `use` modules** — their effect is observed by the modules
  that use them, where it matters.

## Unit testing infrastructure

Two test base modules:

- `ExUnit.Case` — pure tests, `async: true` by default. No DB, no shared
  state.
- `EdgeAdmin.DataCase` (and `EdgeAgent.DataCase`) — DB-backed tests,
  `async: false`. Sandbox transaction rolls back after each test. Used for
  filters, checks, and any function whose contract is "this query returns
  these rows."

Use whichever the function under test requires. Default to `ExUnit.Case`.

## The mock exception

Mox is allowed in **one narrow case**: when a module is explicitly designed
with a behaviour callback so the production code can dispatch to a
configurable module at compile time, and you're testing that dispatch logic.

The two existing examples (`EdgeAdmin.Admins.Metadata` → `MetadataMock`,
`EdgeAdmin.Nodes` → `NodesMock`) are wired via `Application.compile_env` and
the test environment swaps the module. In those cases, Mox is testing the
*real* dispatch behaviour, not constructing fake interactions.

If you need a mock for any other reason — to stand up a fake context, a
fake HTTP server, a fake Netmaker — that test doesn't belong here. Add it
to the staging test plan instead.

## Promote-to-public for testability

When a module's contract lives in a `defp`, prefer promoting it to `def`
with `@doc false` and a real `@spec` over leaving it untestable. The
function is then a real part of the module's API surface (a friend's API,
not strangers') with documented behaviour, and the test pins the contract.

We've done this for ~40 helpers across `edge_admin/`. Examples:

- `EdgeAdmin.Admins.normalise_cluster/1` — Netmaker→admin shape transform.
- `EdgeAdminWeb.Plugs.Http.Handler.filter_hop_by_hop_headers/1` and
  friends — RFC 7230 header logic.
- `EdgeAdmin.Vpn.zombie_node?/4` — safety-critical predicate.
- `EdgeAdminWeb.Plugs.RenderOpenApiSpec.filter_internal_paths/1` —
  security-adjacent (keeps internal endpoints out of public docs).

Don't promote functions that are genuinely implementation details (helpers
that compose with their caller, formatting trivia). Promote contracts.

## Property of a good unit test in this codebase

A unit test should:

- Pin a contract that would silently regress if changed.
- Read like documentation of the function's behaviour.
- Run in milliseconds.
- Be deterministic (no time-of-day dependencies, no random IPs colliding —
  pin them when fixtures share a unique constraint).
- Catch a real bug class, not just exercise pattern-match plumbing.

If a test exists only because we want code coverage, it's noise. We removed
~1500 lines of redundant JSON-renderer tests during the admin pass for
exactly this reason — they duplicated View + ResponseEnvelope coverage that
already lived in tested modules.

## Applies to edge sub-codebases

This policy applies to every Elixir application in the repo:

- `edge_admin/` — covered (see [test-review.md](./test-review.md)).
- `edge_agent/` — same rule applies; future test work should follow this
  policy.

Keep the unit suite tight, the contracts pinned, the wiring trusted to dev
and QA on staging.
