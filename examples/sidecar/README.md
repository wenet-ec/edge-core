# Edge Agent — Sidecar Deployment

Run the Edge Agent as a sidecar container alongside your existing workload.
The agent joins the WireGuard VPN mesh and exposes its proxy servers to other
containers in the same Docker network — without requiring `network_mode: host`.

This was not the original design intent but has been tested and works.

## What you get

- **VPN mesh membership** — the container stack joins the WireGuard mesh
- **HTTP proxy** at `edge_agent:43128` — reach any VPN node from your app container
- **SOCKS5 proxy** at `edge_agent:41080` — same, for non-HTTP protocols
- **SSH access** into the agent container on port 40022

## What doesn't apply in this mode

- **Command execution** — commands run inside the agent container, not your app
- **Host metrics** — reflects the container's view, not the underlying machine

## Quick start

```bash
cp .env.example .env
# fill in PUBLIC_ENROLLMENT_KEY_URLS
docker compose up -d
```

## Using the proxy from your app container

From any container in the same network, route traffic through the agent:

```bash
# Reach a VPN node directly
curl -x http://edge_agent:43128 http://node-abc.cluster-prod.nm.internal:8080/

# Set globally for all requests in the container
export http_proxy=http://edge_agent:43128
export https_proxy=http://edge_agent:43128
```

## Key differences from the standard deployment

| | Standard (`network_mode: host`) | Sidecar (bridge) |
|---|---|---|
| Network namespace | Host | Pod / stack |
| `USE_RANDOM_ID` | Optional | Required |
| Identity source | Host persistent ID | Random (host ID not meaningful) |
| Port collisions | Possible on multi-agent hosts | None (isolated namespace) |
| Command execution | Runs on host machine | Runs in agent container |
| Host metrics | Full host visibility | Container view only |

## Requirements

The agent needs these regardless of deployment mode:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE
sysctls:
  - net.ipv4.ip_forward=1
  - net.ipv4.conf.all.src_valid_mark=1
  - net.ipv6.conf.all.forwarding=1
volumes:
  - /dev/net/tun:/dev/net/tun   # wireguard-go needs this to create a TUN interface
privileged: true
```

## Files in this directory

Browse the actual files on GitHub:

| File | Purpose |
| --- | --- |
| [`docker-compose.yml`](https://github.com/wenet-ec/edge-core/blob/main/examples/sidecar/docker-compose.yml) | Sidecar agent compose. Bridge networking, no `network_mode: host` |
| [`.env.example`](https://github.com/wenet-ec/edge-core/blob/main/examples/sidecar/.env.example) | Required env vars. Copy to `.env` and fill in |

Or browse the whole directory: [`examples/sidecar/`](https://github.com/wenet-ec/edge-core/tree/main/examples/sidecar).
