# Edge Core

A comprehensive edge computing infrastructure management platform that provides secure command execution, VPN connectivity, and metrics collection across distributed edge nodes.

## Architecture

Edge Core consists of several integrated services:

- **Edge Admin** - Central management server for nodes, commands, and configurations
- **Edge Agent** - Lightweight agent running on edge nodes for command execution and metrics
- **Edge VPN** - Secure mesh networking using Headscale (Tailscale alternative)
- **Edge Metrics** - Prometheus-based metrics collection and storage
- **Tailscale Integration** - VPN connectivity and network management

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Development on WSL or Linux is recommended

```sh
docker --version
docker compose version
```

### Development Environment

Start all services:

```sh
docker compose -f deploy/local/web.yml up --build --remove-orphans
```

### Service Endpoints

- **Edge Admin API**: http://localhost:4000
- **Edge Agent API**: http://localhost:4400 
- **VPN Management**: http://localhost:8081
- **Headscale**: http://localhost:8080
- **Metrics Storage**: http://localhost:8428
- **Metrics Collector**: http://localhost:8429

## Development

### Running Tests

Run admin tests:
```sh
docker compose -f deploy/local/web.yml run --rm edge_admin_test
```

Run agent tests:
```sh
docker compose -f deploy/local/web.yml run --rm edge_agent_test
```

### Manual Testing

Use Docker Compose for all operations:
```sh
# Compile admin
docker compose -f deploy/local/web.yml run --rm edge_admin mix compile

# Run specific services
docker compose -f deploy/local/web.yml run --rm [service]
docker compose -f deploy/local/web.yml exec [service]
```

### API Documentation

API specifications are available in the repository:
- `headscale-api-0.26.1.json` - VPN management API
- Check individual service controllers for detailed endpoints

## Features

### Node Management
- Automatic node enrollment and discovery
- SSH key and username management
- Node health monitoring and metrics

### Command Execution
- Remote command execution across nodes
- Target-specific or broadcast commands
- Command execution tracking and retry logic

### VPN Connectivity
- Secure mesh networking with Headscale
- Automatic reconnection and connectivity checking
- Key rotation and management

### Metrics Collection
- Prometheus-based metrics collection
- CPU, memory, disk, and network monitoring
- VictoriaMetrics for storage and querying

## Production Deployment

Production configuration is available in `deploy/production/`:
- `edge.yml` - Main production services
- `cloud.yml` - Cloud-specific deployment

## Contributing

This project uses Elixir/Phoenix for the core services and Go for metrics/VPN components. All development should be done through Docker Compose to ensure consistency.
