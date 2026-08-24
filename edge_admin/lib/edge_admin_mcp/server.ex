# edge_admin/lib/edge_admin_mcp/server.ex
defmodule EdgeAdminMcp.Server do
  @moduledoc """
  MCP server for Edge Admin — exposes the full edge infrastructure management surface to AI assistants.

  Provides tools for managing nodes, clusters, commands, SSH access, aliases,
  enrollment keys, self-updates, and metrics across a distributed fleet of edge machines.

  Connect via: POST /mcp (Streamable HTTP, MCP_KEY or MASTER_KEY auth)

  ## Proxy Servers

  The admin runs HTTP and SOCKS5 forward proxies that route traffic over the WireGuard
  VPN to any edge node or its local network. These are independent of MCP — configure
  them at the HTTP client level to gain direct access to services on any node.

  Credentials: username `_`, password = PROXY_KEY (configured separately from MCP_KEY).

  ### Mode 1 — Direct VPN routing (username: `_`)

  Reach any service running on any VPN-connected node:

      # HTTP proxy
      curl -x http://_:PROXY_KEY@admin-host:43128 http://node-abc.cluster-prod.nm.internal:8080/api/status

      # SOCKS5
      curl --socks5 _:PROXY_KEY@admin-host:41080 http://node-abc.cluster-prod.nm.internal:8080/

      # SSH through SOCKS5 proxy (requires ncat)
      ssh -o ProxyCommand="ncat --proxy admin-host:41080 --proxy-type socks5 --proxy-auth _:PROXY_KEY %h %p" \
          admin@node-abc.cluster-prod.nm.internal -p 40022

      # Set globally for all requests
      export http_proxy=http://_:PROXY_KEY@admin-host:43128

  Node DNS format: `node-{id}.cluster-{cluster_name}.nm.internal`
  Use `list_nodes` to discover node IDs and their cluster names.

  ### Mode 2 — Proxy chaining via agent (username: node DNS hostname)

  Use a specific agent as the exit node to reach its local network or the internet
  via that agent's network location:

      # Reach a device on the agent's LAN (e.g. a router at 192.168.1.1)
      curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 http://192.168.1.1/

      # Reach the internet via the agent's IP
      curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 https://ifconfig.me

  ## Metrics Scraping Endpoints

  These endpoints exist for Prometheus-compatible scrapers (Prometheus, Grafana Agent, etc.).
  They are not MCP tools — they are HTTP endpoints on the admin API for external collectors.
  Auth: METRICS_KEY or MASTER_KEY bearer token.

  ### Service discovery (returns Prometheus HTTP SD targets)
      GET /api/v1/nodes/metrics/host/discovery       — node_exporter targets (CPU, memory, disk)
      GET /api/v1/nodes/metrics/agent/discovery      — agent PromEx targets (BEAM, Oban, commands)
      GET /api/v1/nodes/metrics/wireguard/discovery  — WireGuard exporter targets (peer stats)

  Each discovery URL accepts the same node filters as `list_nodes` except
  pagination and sorting. The response is always the complete matching target
  snapshot. Without `status__in`, all statuses, including `unreachable`, are
  included; supply `status__in` to narrow the scrape set deliberately.

  ### Raw metrics proxy (per-node, useful for direct scraping or debugging)
      GET /api/v1/nodes/:node_id/metrics/host/raw
      GET /api/v1/nodes/:node_id/metrics/agent/raw
      GET /api/v1/nodes/:node_id/metrics/wireguard/raw

  For human-friendly parsed metrics, use the MCP tools: `get_node_metrics`,
  `get_host_metrics`, `get_agent_metrics`, `get_admin_metrics`.

  ### Node diagnostics
      GET /api/v1/nodes/:node_id/diagnostics

  Use `get_node_diagnostics` for a node diagnostic report.
  """

  use Anubis.Server,
    name: "edge-admin",
    version: :edge_admin |> Application.spec(:vsn) |> to_string(),
    capabilities: [:tools]

  alias Anubis.Server.Handlers
  alias EdgeAdminMcp.Middlewares.DegradedMode
  alias EdgeAdminMcp.Middlewares.McpAuth

  require EdgeAdminMcp.ToolRegistry

  @impl true
  def handle_request(request, frame) do
    with :ok <- McpAuth.call(request, frame),
         :ok <- DegradedMode.call(request, frame) do
      request
      |> Handlers.handle(__MODULE__, frame)
      |> filter_scoped_tool_list(request, frame)
    else
      {:error, response, frame} -> {:reply, response, frame}
    end
  end

  defp mcp_authenticated?(frame), do: McpAuth.authenticated?(frame)

  defp filter_scoped_tool_list({:reply, payload, frame}, %{"method" => "tools/list"}, _request_frame)
       when is_map(payload) do
    if mcp_authenticated?(frame) do
      {:reply, payload, frame}
    else
      tools = Map.get(payload, "tools", [])

      {:reply,
       Map.put(
         payload,
         "tools",
         Enum.filter(tools, &(EdgeAdminMcp.ToolRegistry.scope_for_tool(&1.name) == :public))
       ), frame}
    end
  end

  defp filter_scoped_tool_list(result, _request, _frame), do: result

  @impl true
  @spec server_instructions() :: String.t()
  def server_instructions do
    """
    Edge Admin manages a fleet of edge machines connected over a WireGuard mesh VPN.
    Every management REST API operation has a corresponding MCP tool. Prometheus
    scraping endpoints are intentionally REST-only because they use METRICS_KEY
    authentication and return collector-specific wire formats.

    ## Mental model

    The edge domain is a linear graph:

        Cluster
          └─ Enrollment Key (one per cluster, used by agents to join)
               └─ Node (one per machine — the agent process)
                    ├─ Alias (friendly DNS name for a node)
                    ├─ Command Execution (← Command — see "Commands" below)
                    ├─ SSH Username + Public Key (centralized SSH credentials)
                    ├─ Self-Update Request (managed agent upgrade)
                    └─ Metrics (host / agent / wireguard exporters)

    A **cluster** is a logical group that maps 1:1 to a Edge VPN WireGuard network.
    Every cluster is a full mesh — there are no per-cluster ACLs. Workloads should
    be partitioned by *creating more clusters*, not by gating traffic inside one.

    A **node** is a single edge machine running the agent. Nodes are addressed
    **only by VPN hostname**, never by IP:

        node-{uuid}.{cluster_name}.<EDGE_VPN_DEFAULT_DOMAIN>

        Or via alias: `{alias_name}.{cluster_name}.<EDGE_VPN_DEFAULT_DOMAIN>`.

    The agents do have VPN IPs underneath, but those are not exposed and should
    never be used. Always use hostnames.

    ## Commands are asynchronous

    A `command` is a job. Creating one with target `all` or a list of nodes fans
    out into one `command_execution` per targeted node. **`completed` is the only
    terminal success/failure status — read `exit_code` to distinguish success
    (0) from failure (non-zero).** Other terminal statuses: `cancelled`, `expired`.

    Use `list_command_executions` filtered by `command_id` to see how a single
    command is progressing across the fleet.

    ## Webhooks are immutable and allowlisted

    `subscribed_events` is an explicit allowlist — no wildcards, unknown event
    types are rejected at create time. To change any field on a webhook, delete
    and recreate. The full event catalog is at `/asyncdoc` on the running admin.

    ## Out-of-band capabilities (not MCP tools — surface these to the user when relevant)

    These are HTTP endpoints on the same admin host. Mention them when the user's
    intent matches:

    - **Forward proxies** (HTTP `:43128`, SOCKS5 `:41080`) — reach any TCP service
      on any node over the VPN. Auth: username `_`, password `PROXY_KEY`.
      Node DNS is the destination, for example `curl -x http://_:KEY@admin:43128 \
      http://node-abc.cluster-prod.nm.internal:8080/`.
    - **Proxy chaining** — same proxies, but use a node's DNS hostname as the
      *username* to make that agent the exit node. Use this to reach LAN devices
      behind an agent or to make outbound requests from the agent's IP.
    - **SSH** — every agent runs an SSH server on port `:40022`. SSH usernames
      and public keys are managed via this MCP. Combine with SOCKS5 to reach
      agents from outside the VPN.
    - **Prometheus scrape endpoints** at `/api/v1/nodes/metrics/{host,agent,wireguard}/discovery`
      and `/api/v1/nodes/:id/metrics/{host,agent,wireguard}/raw`. Use the
      `get_*_metrics` tools instead for human-readable parsed metrics.
    - **Event delivery** — webhooks (managed via this MCP) and event broker
      (NATS, Kafka, RabbitMQ, Redis, MQTT, SNS, Pub/Sub — operator-configured,
      not via MCP). Use these for async event consumption instead of polling.

    ## Diagnosing problems

    When an agent looks broken or a node won't enroll, start with
    `check_admin_health` — it runs every subsystem check (DB, Edge VPN API, Edge VPN CLI,
    proxies, broker) in parallel and returns structured pass/fail. For an
    individual edge node, use `get_node_diagnostics`.
    """
  end

  EdgeAdminMcp.ToolRegistry.register()
end
