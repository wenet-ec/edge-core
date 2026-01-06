# Edge Core

A comprehensive edge computing infrastructure management platform that provides secure command execution, VPN connectivity, proxy servers, SSH access, and metrics collection across distributed edge nodes.

## Architecture

Edge Core consists of two main applications and shared libraries:

### Applications
- **Edge Admin** (`./edge_admin/`) - Central management server (Elixir/Phoenix)
  - Node enrollment and management
  - Command orchestration and execution tracking
  - SSH credential management
  - Proxy server coordination
  - Metrics aggregation
  - VPN cluster management

- **Edge Agent** (`./edge_agent/`) - Lightweight agent for edge nodes (Elixir/Phoenix)
  - Command execution
  - Local proxy servers (HTTP/SOCKS5)
  - SSH server
  - Metrics collection and reporting
  - VPN connectivity via Netmaker

### Shared Libraries
- **Nexmaker** (`./nexmaker/`) - Shared library for interacting with Netmaker API and netclient CLI
- **Reference Code** (`./netmaker/`) - Latest Netmaker and netclient source code for reference

### Infrastructure
- **VPN** - Netmaker-based secure mesh networking
- **Metrics** - VictoriaMetrics for storage and querying
- **Message Broker** - EMQX for agent-admin communication

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Development on WSL or Linux is recommended
- No Elixir, Mix, or Go required - all operations run through Docker Compose

```sh
docker --version
docker compose version
```

### Development Environment

Edge Core has two deployment configurations:

#### Cloud Services (Admin + Infrastructure)
Start the admin server and supporting infrastructure:

```sh
docker compose -f deploy/local/cloud.yml up --build
```

#### Edge Services (Agent)
Start edge agents in a separate terminal:

```sh
docker compose -f deploy/local/edge.yml up --build
```

#### Helper Script
Use the convenience script to manage both configurations:

```sh
./bin/run cloud up    # Start cloud services
./bin/run edge up     # Start edge services
./bin/run cloud down  # Stop cloud services
```

### Service Endpoints

**Cloud Services:**
- **Edge Admin API**: http://localhost:4000
- **Netmaker API**: http://localhost:8081
- **Netmaker UI**: http://localhost:8082
- **EMQX Broker**: http://localhost:1883 (MQTT), http://localhost:18083 (Dashboard)
- **Metrics Storage**: http://localhost:8428
- **Postgres DB**: localhost:5432

**Edge Services:**
- **Edge Agent API**: http://localhost:4400
- **Edge Agent 2 API**: http://localhost:4401
- **Container Registry**: http://localhost:45000
- **Watchtower**: (auto-updates containers)

## Development

### Running Tests

Run admin tests:
```sh
docker compose -f deploy/local/cloud.yml run --rm edge_admin_test
```

Run agent tests:
```sh
docker compose -f deploy/local/edge.yml run --rm edge_agent_test
```

### Working with the Codebase

All development operations use Docker Compose:

```sh
# Compile admin
docker compose -f deploy/local/cloud.yml run --rm edge_admin mix compile

# Compile agent
docker compose -f deploy/local/edge.yml run --rm edge_agent mix compile

# Run Elixir shell in admin
docker compose -f deploy/local/cloud.yml run --rm edge_admin iex -S mix

# Execute commands in running containers
docker compose -f deploy/local/cloud.yml exec edge_admin bash

# View logs
docker compose -f deploy/local/cloud.yml logs -f edge_admin
docker compose -f deploy/local/edge.yml logs -f edge_agent
```

## Features

### Node Management
- Automatic node enrollment with enrollment keys
- Node discovery via MQTT and VPN mesh
- SSH key and username management
- Node health monitoring and metrics
- Cluster-based node grouping

### Command Execution
- Remote command execution across nodes
- Target-specific or broadcast commands
- Command execution tracking and results collection
- Retry logic and error handling
- Real-time command status updates

### Proxy Servers
- HTTP and SOCKS5 proxy servers on agents
- Admin-coordinated proxy management
- Configurable proxy destinations
- Automatic proxy health checking
- Sensitive destination blocking

### SSH Access
- Dynamic SSH server on agents
- Credential management via admin
- Username and public key distribution
- Secure remote shell access to edge nodes

### VPN Connectivity
- Netmaker-based secure mesh networking
- Automatic enrollment and cluster management
- Connectivity checking and auto-reconnection
- Multi-cluster support
- Integration with netclient CLI

### Metrics Collection
- Prometheus-based metrics collection
- CPU, memory, disk, and network monitoring
- VictoriaMetrics for efficient storage and querying
- Metrics aggregation at admin level
- Per-node and cluster-wide metrics

### Self-Updates
- Watchtower integration for automatic container updates
- Version tracking and rollback support
- Coordinated update scheduling

## Production Deployment

Production configuration is available in `deploy/production/`:
- `cloud.yml` - Admin and infrastructure services
- `edge.yml` - Agent services
- Environment-specific configurations in `.envs/`

## Technology Stack

- **Backend**: Elixir/Phoenix (Admin & Agent)
- **VPN**: Netmaker (Go-based mesh VPN)
- **Message Broker**: EMQX (MQTT)
- **Metrics**: VictoriaMetrics, Prometheus exporters
- **Database**: PostgreSQL
- **Container Orchestration**: Docker Compose
- **Shared Library**: Nexmaker (Elixir)

## Contributing

All development must be done through Docker Compose to ensure consistency. The project does not require local Elixir, Mix, or Go installations.
