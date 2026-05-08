# Testing Policy

## Overview

Edge Core has two testing tiers, with a clear split of responsibility.

**Unit tests (this repo)** cover **pure logic only**: things we can extract
out of the codebase and verify deterministically with inputs and expected
outputs. They run in milliseconds, in-process, with no external dependencies.

**System and integration tests** live outside this repo. The dev and QA
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
  (changeset error rendering, event catalog, response envelope shape,
  blocked operations under degraded mode). One representative test per
  shared module.
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
- `EdgeAdmin.DataCase` / `EdgeAgent.DataCase` — DB-backed tests,
  `async: false`. Sandbox transaction rolls back after each test. Used for
  filters, checks, and any function whose contract is "this query returns
  these rows."

Use whichever the function under test requires. Default to `ExUnit.Case`.

### Adapter parity

Admin runs against PostgreSQL by default and SQLite when
`DB_ADAPTER=sqlite`. Both adapters must stay green. The DB-backed test
suite is adapter-agnostic by design:

- All filters use `EdgeAdmin.Query.case_insensitive_like/2` (a `lower(?) LIKE
  lower(?)` shim) instead of `ilike/2`. SQLite doesn't have `ilike`.
- Fixtures truncate timestamps to `:second` so PG (microsecond) and SQLite
  (no native datetime, stored as text) agree.
- Fixtures use `Ecto.Changeset.change/2` for fields that need an explicit
  `nil`. Plain `struct/2` insert keeps schema-level defaults — fine on
  PG, but the same value lands as the default on disk in SQLite too, so
  use `change/2` whenever the test contract is "this row's column is NULL."
- Run the SQLite suite with `VARIANT=lite ./bin/run cloud admin:test`. The
  `bin/run` harness wipes the test DB file before each lite run so
  in-place migration edits never desync source from the on-disk schema.

### Avoiding test pollution

When inserting multiple rows that share a unique constraint (cluster IP
ranges, names, keys), pin distinct values explicitly rather than rolling
random ones. With 4+ inserts in one test, random rolls collide often
enough to flake CI. The unit-tested filter suite uses fixed `10.10.x.0/24`
ranges in a setup block for this reason.

## The mock exception

Mox is allowed in **one narrow case**: when a module is explicitly designed
with a behaviour callback so the production code can dispatch to a
configurable module at compile time, and you're testing that dispatch
logic.

Existing examples are `EdgeAdmin.Admins.Metadata` → `MetadataMock` and
`EdgeAdmin.Nodes` → `NodesMock`, wired via `Application.compile_env` and
the test environment swapping the module. In those cases, Mox is testing
the *real* dispatch behaviour, not constructing fake interactions.

If you need a mock for any other reason — to stand up a fake context, a
fake HTTP server, a fake Netmaker — that test doesn't belong here. Add it
to the staging test plan instead.

## Promote-to-public for testability

When a module's contract lives in a `defp`, prefer promoting it to `def`
with `@doc false` and a real `@spec` over leaving it untestable. The
function is then a real part of the module's API surface (a friend's API,
not strangers') with documented behaviour, and the test pins the contract.

Examples of contracts worth promoting:

- Pure helpers that classify, parse, or normalise (`normalize_key/1`,
  `classify_create_network_400/1`, `extract_message/1`).
- Security-adjacent predicates (`zombie_node?/4`,
  `filter_internal_paths/1`).
- Cross-surface envelope builders (`build_envelope/1`,
  `paginated/3`).

Don't promote functions that are genuinely implementation details (helpers
that compose with their caller, formatting trivia). Promote contracts.

### Credo gotcha for env-touching tests

Credo's `Credo.Check.Warning.ApplicationConfigInModuleAttribute` flags
`Application.put_env/3` and `Application.get_env/2` even inside test
bodies. Use the fully-qualified `Elixir.Application.put_env/3` and
`Elixir.Application.get_env/2` form to dodge the heuristic. Tests that
snapshot/restore application env should also be `async: false` since the
env is global.

## Property of a good unit test in this codebase

A unit test should:

- Pin a contract that would silently regress if changed.
- Read like documentation of the function's behaviour.
- Run in milliseconds.
- Be deterministic (no time-of-day dependencies, no random IPs colliding —
  pin them when fixtures share a unique constraint).
- Catch a real bug class, not just exercise pattern-match plumbing.

If a test exists only because we want code coverage, it's noise. Tests
that duplicate coverage of upstream modules they wrap (e.g. JSON
renderers around already-tested Views) should be removed, not maintained.

## Applies to all sub-codebases

This policy applies to every Elixir application in the repo:

- `edge_admin/`
- `edge_agent/`
- `nexmaker/`

Keep the unit suite tight, the contracts pinned, the wiring trusted to dev
and QA on staging.
