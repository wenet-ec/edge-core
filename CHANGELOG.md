# Changelog

All notable changes to Edge Core are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.2.0] — first stable release

**v0.2.0 is a ground-up redesign.** The architecture, data model, deployment shape, and public API all changed substantially from `v0.1.0`. There is **no upgrade path from v0.1.0** — treat this as a new project and start fresh.

What v0.2.0 actually is, in one paragraph:

A masterless, peer-clustered Elixir/Phoenix admin that orchestrates command execution, SSH access, HTTP/SOCKS5 forward proxying, and Prometheus metrics aggregation across edge nodes connected via a WireGuard mesh (Netmaker + DERP-fork netclient). PostgreSQL-or-SQLite, runtime-switched. Ships an MCP server for AI assistants and a CloudEvents-based event bus with seven broker adapters plus user-configurable webhooks. Validated in private deployments before this public release.

For the full picture rather than a feature list:

- Architecture and design rationale: [`docs/architecture.md`](docs/architecture.md)
- Day-to-day operator surface: [`docs/guide.md`](docs/guide.md)
- Deployment shapes: [`examples/`](examples/)
- Event catalog: [`docs/admin-asyncapi-v0.2.0.md`](docs/admin-asyncapi-v0.2.0.md) or `/asyncdoc` on a running admin
- REST API: [`docs/admin-openapi-v0.2.0.json`](docs/admin-openapi-v0.2.0.json) or `/swaggerui` on a running admin
- MCP tool catalog: [`docs/admin-mcp-v0.2.0.md`](docs/admin-mcp-v0.2.0.md) or `tools/list` on `POST /mcp` for the live surface

Image tags `ghcr.io/wenet-ec/edge_admin:v0.2.0` and `ghcr.io/wenet-ec/edge_agent:v0.2.0`.

## [v0.1.0] — beta (deprecated)

Internal/experimental beta with a different architecture. Superseded entirely by v0.2.0. Not recommended for any use; kept only for git history.

[v0.2.0]: https://github.com/wenet-ec/edge-core/releases/tag/v0.2.0
[v0.1.0]: https://github.com/wenet-ec/edge-core/releases/tag/v0.1.0
