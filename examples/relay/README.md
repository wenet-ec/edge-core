# Self-hosted DERP Relay

Two services that together let your fleet route WireGuard traffic through your own infrastructure when direct UDP fails (symmetric NAT, ISP UDP blocking, restricted networks):

- **`edge_relay`** — a [DERP](https://tailscale.com/docs/reference/derp-servers) relay node (our fork of `derper`). Speaks WireGuard-over-HTTPS on port 443 and STUN on UDP 3478.
- **`edge_relay_map`** — a tiny Caddy that serves your relay map JSON at `https://<host>/derpmap/default`. Admins and agents fetch this to learn which relays exist.

You only need this if you want **geo-local relays** or **full infrastructure ownership**. For most deployments, Tailscale's public DERP infrastructure is already configured by default and handles symmetric NAT transparently — running your own is an upgrade, not a prerequisite.

## When to deploy this

- You operate in a region where Tailscale's public DERPs add unacceptable latency
- You have a regulatory or policy requirement to keep all traffic on infrastructure you control
- You want to add capacity in addition to (not instead of) the public relays

If none of those apply, skip this directory.

## Architecture

The two services run on **two separate machines**, because each owns ports 80+443 exclusively for ACME challenges and TLS:

```
Machine A — edge_relay        (DERP_HOSTNAME=edge-relay-1.yourdomain.com)
  → 443/tcp   DERP relay over HTTPS
  → 80/tcp    ACME HTTP-01 challenge
  → 3478/udp  STUN

Machine B — edge_relay_map    (DERP_MAP_HOSTNAME=edge-relay-map-1.yourdomain.com)
  → 443/tcp   Serves derp-map.json at /derpmap/default
  → 80/tcp    ACME HTTP-01 challenge
```

You can run both on the same machine if you front them with a reverse proxy that does SNI routing — but that complication isn't worth it; just use two cheap VMs.

## Quick start

```bash
cp .env.example .env
# fill in DERP_HOSTNAME, DERP_ACME_EMAIL, DERP_MAP_HOSTNAME

# Edit derp-map.json — set HostName to your DERP_HOSTNAME, update RegionCode/RegionName
$EDITOR derp-map.json

# Machine A
docker compose up -d edge_relay

# Machine B
docker compose up -d edge_relay_map
```

Verify the relay map is being served:

```bash
curl https://edge-relay-map-1.yourdomain.com/derpmap/default
```

## Wire it into your admin

Once both services are up and the map is reachable, point your admin at it via `CORE_DERP_MAP_URLS` in `.edge_admin`:

```env
CORE_DERP_MAP_URLS=https://edge-relay-map-1.yourdomain.com/derpmap/default
```

The admin's `/start` script exports this to netclient's `DERP_MAP_URLS` at boot. Agents learn the same ordered source list through their authenticated settings refresh.

`CORE_DERP_MAP_URLS` is an ordered list for **one complete canonical map**. It is not a list of map fragments: the first reachable URL is used, and maps from multiple URLs are never merged.

### Migrate a map hostname

Use two URLs only while moving the hostname that serves the map:

```env
CORE_DERP_MAP_URLS=https://new-map.example.com/derpmap/default,https://old-map.example.com/derpmap/default
```

Both URLs must serve the same complete canonical map. Deploy the new setting, then keep both URLs live for at least 10 minutes (and longer for offline nodes) so Admins and Agents converge. Retire the old URL only after that window.

### Change the map contents

Do this separately from a hostname migration. First finish the hostname migration above. Then update `derp-map.json` on every active map server so all of them serve the same new complete map, and allow the fleet another refresh window to converge.

Do not change the source URLs and map contents in one rollout. Nodes using different map versions can select different DERP relays for the same peer pair. This does not stop direct WireGuard connectivity or Admin fallback communication through `ADMIN_URLS`; only peer-to-peer traffic that requires DERP can be briefly disrupted while the maps converge.

## Network requirements

The relay machine needs these ports **open to the public internet**:

| Port   | Protocol | Purpose                              |
| ------ | -------- | ------------------------------------ |
| `443`  | TCP      | DERP-over-HTTPS                      |
| `80`   | TCP      | Let's Encrypt HTTP-01 challenge      |
| `3478` | UDP      | STUN (helps direct connections form) |

The map server needs:

| Port  | Protocol | Purpose                         |
| ----- | -------- | ------------------------------- |
| `443` | TCP      | HTTPS for `/derpmap/default`    |
| `80`  | TCP      | Let's Encrypt HTTP-01 challenge |

**Do not put a reverse proxy or Cloudflare orange-cloud in front of port 443** on either service. Both terminate TLS themselves (derper for relay, Caddy for the map) and DERP's protocol upgrade inside TLS doesn't survive proxying. Cloudflare DNS-only (grey cloud) is fine.

## Files in this directory

Browse the actual files on GitHub:

| File                 | Purpose                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| [`docker-compose.yml`](https://github.com/wenet-ec/edge-core/blob/main/examples/relay/docker-compose.yml) | Two-service compose file — run one service per machine.                                          |
| [`.env.example`](https://github.com/wenet-ec/edge-core/blob/main/examples/relay/.env.example)             | Required env vars: hostnames, ACME email.                                                        |
| [`Caddyfile`](https://github.com/wenet-ec/edge-core/blob/main/examples/relay/Caddyfile)                   | Caddy config for the map server — serves `derp-map.json` at `/derpmap/default`.                  |
| [`derp-map.json`](https://github.com/wenet-ec/edge-core/blob/main/examples/relay/derp-map.json)           | The relay map itself. Edit `HostName` to match your `DERP_HOSTNAME`. Add more regions as needed. |

Or browse the whole directory: [`examples/relay/`](https://github.com/wenet-ec/edge-core/tree/main/examples/relay).

## Adding more relays

The map JSON supports multiple regions and multiple nodes per region:

```json
{
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "us-east",
      "RegionName": "US East",
      "Nodes": [
        {
          "Name": "900a",
          "RegionID": 900,
          "HostName": "edge-relay-1.yourdomain.com",
          "DERPPort": 443,
          "CanPort80": true
        }
      ]
    },
    "901": {
      "RegionID": 901,
      "RegionCode": "eu-west",
      "RegionName": "EU West",
      "Nodes": [
        {
          "Name": "901a",
          "RegionID": 901,
          "HostName": "edge-relay-2.yourdomain.com",
          "DERPPort": 443,
          "CanPort80": true
        }
      ]
    }
  }
}
```

Each node needs its own VM running the `edge_relay` service with its own `DERP_HOSTNAME`. Region IDs ≥ 900 are the convention for self-hosted relays — public Tailscale DERPs use lower numbers.

After editing `derp-map.json`, restart `edge_relay_map` to pick up the file. Follow the map-content rollout above rather than relying on Admin restarts: Admins and Agents refresh their advertised configuration and map cache independently.

## Limitations

- **Userspace WireGuard only.** DERP relay fallback only works through `wireguard-go`. The admin always uses userspace; agents using kernel-mode WireGuard won't fall back through DERP.
- **No HA on the map server.** It's a single Caddy serving one JSON file — if it goes down, _new_ admin/agent boots can't fetch the map. Already-running netclients keep using the relay they already know about. Run a second map server on a different host if you need HA at the discovery layer.
