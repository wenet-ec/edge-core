# Grafana Dashboards

Two dashboard JSON files live here. Import them manually into your Grafana instance:
**Dashboards → Import → Upload JSON file**, then select your Prometheus datasource.

---

## `edge_admin.json` — EdgeAdmin Custom Metrics (v0.2.0)

Business and operational metrics scraped from the edge_admin PromEx endpoint.

| Section | Panels | What it shows |
| ------- | ------ | ------------- |
| **Bootstrap & Discovery** | Bootstrap Steps Rate, Bootstrap Duration (p95), Successful Peer Connections, Discovery Rate | Admin startup step counts/durations; Erlang peer connect and DNS resolution rates during peer discovery |
| **Metadata & Cluster Management** | Recomputation Duration, Assigned Clusters, Orphaned Clusters, Admin Cluster Status | How long metadata recomputation takes; how many clusters this admin owns; whether the admin is degraded |
| **Proxy Server** | Connection Rate, Session Duration, Routing Mode Split, Connection Rate by Cluster | HTTP + SOCKS5 proxy traffic; local vs remote routing; direct vs chain mode; per-cluster breakdown; session duration percentiles |
| **Node Health** | Health Check Duration, Unhealthy/Unreachable Nodes, Health Check Rate by Result | How quickly individual node health checks resolve; how many nodes came back unhealthy in the last check cycle |
| **Command Execution** | Execution Lifecycle (created/delivered/completed/expired), Execution Duration | Full command pipeline rate — from execution creation through agent delivery to result received; duration p50/p95/p99 by exit code category (success/failure/timeout/cancelled) |
| **Quantum Scheduler** | Job Execution Rate, Job Duration (p95), Job Exception Rate | Quantum scheduler job health per job name; useful for spotting jammed or slow recurring jobs |
| **VPN & Command Delivery** | Zombie Admin Cleanup Rate, Zombies Deleted, Delivery Batch Rate, Executions Delivered | Netmaker zombie admin cleanup; delivery scheduler batch run results and per-batch execution count |
| **Gateway** | Gateway Connection Events, Active Gateway Connections, Gateway Scrape Rate | Gateway GenServer connect/disconnect events per cluster; active gateway count; metrics scrape success/error by type (host/agent/wireguard) |
| **SSH** | SSH Verification Rate, SSH Failures (Window) | Per-auth-method (password/public_key) verification success and failure rates; failure count alerting for brute-force detection |
| **Cluster Reconciliation** | Reconciliation Rate, Reconciliation Duration | Netmaker ↔ DB sync run rate and duration per cluster; error rate for diagnosing Netmaker API timeouts |
| **Self-Updates** | Requests Completed, Nodes Triggered vs Failed | Self-update request processing rate by targeting type; last-request outcome (triggered vs failed nodes) |

Default datasource UID: `edge_admin_prometheus` — rename the variable if yours differs.

---

## `edge_agent.json` — Edge Agent Metrics (v0.2.0)

Agent-side metrics scraped from the edge_agent PromEx endpoint.

| Section | What it shows |
| ------- | ------------- |
| **Bootstrap & Discovery** | Agent registration rate; admin discovery scan rate |
| **Command Execution** | Command execution rate and duration; sync and report worker activity; pending/sent counts |
| **Proxy Server** | HTTP + SOCKS5 connection rates; session duration (p95); blocked request counts |
| **SSH Server** | Auth rate (password vs public key); connection rate; session duration |
| **VPN** | VPN config pull rate by result (daily backstop for DNS recovery after netclient restart) |
| **Health Check (HTTP Fallback)** | Health check report rate by result — only fires when VPN is down and agent is using HTTP fallback to reach admin |

---

## Datasource naming

Both dashboards use a `${datasource}` variable that defaults to `edge_admin_prometheus`. If your Prometheus datasource has a different name, update the variable default after import under **Dashboard settings → Variables**.
