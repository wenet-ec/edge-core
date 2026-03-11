# edge_admin/lib/edge_admin/edge_clusters/gateway.ex
defmodule EdgeAdmin.EdgeClusters.Gateway do
  @moduledoc """
  Gateway GenServer managing VPN connection and HTTP communication with an edge cluster.

  One Gateway process runs per cluster assigned to this admin. Each Gateway maintains
  a persistent VPN connection to its cluster and provides HTTP client functions for
  admin-to-agent communication.

  ## Key Concepts

  - **VPN Connection**: Direct host-to-network join via Netmaker API (no enrollment keys)
  - **Cross-Admin Routing**: syn registry enables routing requests to the correct admin
  - **HTTP Client**: Provides helper functions for metrics scraping and agent commands
  - **Non-blocking Operations**: All HTTP/TCP operations use Task.async to prevent head-of-line blocking
  - **Lifecycle**: Started/stopped by EdgeClusters coordinator based on metadata assignments

  ## Responsibilities

  1. **VPN Management**
     - Join cluster network on startup (creates Netmaker node)
     - Leave cluster network on shutdown (deletes node, preserves host)
     - Monitor network connectivity

  2. **syn Registration**
     - Register with key `{:gateway, admin_name, cluster_name}`
     - Enable cross-admin request routing
     - Automatic deregistration on process exit

  3. **HTTP Communication**
     - Scrape host metrics (Node Exporter)
     - Scrape agent metrics (PromEx)
     - Scrape WireGuard metrics
     - Trigger agent self-updates
     - Send command executions
     - Request SSH credential verification

  ## Cross-Admin Routing

  Gateways register in syn to enable distributed request routing:

      # Find the Gateway that owns a cluster
      :syn.lookup(:cluster_scope, {:gateway, "admin-abc", "cluster-prod"})
      #=> {pid, metadata}

      # Use from code
      {:ok, gateway_pid} = Gateway.lookup("cluster-prod")
      Gateway.scrape_host_metrics(gateway_pid, node)

  ## VPN Lifecycle

  - **Join**: `Vpn.add_host_to_network(host_id, network_name)` - Direct API call
  - **Leave**: `Vpn.remove_host_from_network(host_id, network_name)` - Removes node, keeps host
  - **No Enrollment Keys**: Uses existing host credentials from admin cluster

  ## Examples

      # Gateway is started by EdgeClusters coordinator
      DynamicSupervisor.start_child(Supervisor, {Gateway, "cluster-prod"})

      # Lookup and use Gateway
      {:ok, gateway_pid} = Gateway.lookup("cluster-prod")
      {:ok, metrics} = Gateway.scrape_host_metrics(gateway_pid, node)

      # Cross-admin routing (automatic)
      # Admin A owns cluster-prod
      # Admin B needs to scrape metrics from node in cluster-prod
      # Admin B's request automatically routes to Admin A's Gateway
  """

  use GenServer

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.ProxyServers.RemoteTunnel
  alias EdgeAdmin.Vpn

  require Logger

  # HTTP request timeout options for agent communication
  defp agent_request_options do
    [
      receive_timeout: Application.get_env(:edge_admin, :http_agent_receive_timeout),
      connect_options: [timeout: Application.get_env(:edge_admin, :http_agent_connect_timeout)],
      retry: false
    ]
  end

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Starts a Gateway process for the given cluster.

  The Gateway will join the cluster's VPN network during initialization.
  """
  def start_link(cluster_name) do
    GenServer.start_link(__MODULE__, cluster_name)
  end

  @doc """
  Looks up the Gateway process for a given cluster.

  Returns the Gateway PID for the admin that owns the cluster.
  Uses cluster ownership from Metadata to determine which admin's Gateway to use.

  ## Parameters
  - cluster_name: The edge cluster name

  ## Returns
  - `{:ok, gateway_pid}` - Gateway process found
  - `{:error, :gateway_not_found}` - No Gateway registered for this cluster
  - `{:error, :no_owner}` - Cluster not assigned to any admin

  ## Examples

      {:ok, pid} = Gateway.lookup("cluster-abc123")
      Gateway.scrape_metrics(pid, node)
  """
  def lookup(cluster_name) do
    case Metadata.get_cluster_owner(cluster_name) do
      nil ->
        {:error, :no_owner}

      admin_name ->
        case :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_name}) do
          {pid, _metadata} ->
            {:ok, pid}

          :undefined ->
            # Ownership may have changed between the ETS read above and the syn lookup
            # (TOCTOU window during topology recomputation). Fall back to a direct syn
            # scan across all registered gateways for this cluster_name.
            scan_for_gateway(cluster_name)
        end
    end
  end

  defp scan_for_gateway(cluster_name) do
    # Ownership changed between the ETS read and the syn lookup. Try all known
    # admins to find whichever one now owns the gateway for this cluster.
    admin_names = Map.keys(Metadata.get_edge_clusters())

    result =
      Enum.find_value(admin_names, fn admin_name ->
        case :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_name}) do
          {pid, _metadata} -> {:ok, pid}
          :undefined -> nil
        end
      end)

    result || {:error, :gateway_not_found}
  end

  @doc """
  Scrapes host metrics from a node's Node Exporter.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, host_metrics_port

  ## Returns

  - {:ok, metrics_text} - Raw Prometheus metrics
  - {:error, reason} - HTTP error or network failure
  """
  def scrape_host_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_host_metrics, node}, 10_000)
  end

  @doc """
  Scrapes agent application metrics from a node's PromEx endpoint.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, http_port, api_token

  ## Returns

  - {:ok, metrics_text} - Raw Prometheus metrics
  - {:error, reason} - HTTP error or network failure
  """
  def scrape_agent_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_agent_metrics, node}, 10_000)
  end

  @doc """
  Scrapes WireGuard metrics from a node's WireGuard Exporter endpoint.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, wireguard_metrics_port

  ## Returns

  - {:ok, metrics_text} - Raw Prometheus metrics
  - {:error, reason} - HTTP error or network failure
  """
  def scrape_wireguard_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_wireguard_metrics, node}, 10_000)
  end

  @doc """
  Triggers self-update on an agent.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, http_port, api_token

  ## Returns

  - :ok - Update triggered successfully
  - {:error, reason} - HTTP error or network failure
  """
  def trigger_self_update(gateway_pid, node) do
    GenServer.call(gateway_pid, {:trigger_self_update, node}, 15_000)
  end

  @doc """
  Cancels a command execution on an agent.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, http_port, api_token
  - execution_id: Command execution ID to cancel

  ## Returns

  - :ok - Cancellation request sent successfully
  - {:error, reason} - HTTP error or network failure
  """
  def cancel_execution(gateway_pid, node, execution_id) do
    GenServer.call(gateway_pid, {:cancel_execution, node, execution_id}, 15_000)
  end

  @doc """
  Establishes TCP connection to a target through the Gateway's VPN.

  Gateway is a pure network abstraction - it only handles VPN connectivity.
  Returns {:ok, socket} with ownership transferred to caller, or error.

  The caller is responsible for:
  - Managing the returned socket
  - Handling cross-node communication if needed
  - Setting up any streaming/forwarding logic

  - target_host: VPN DNS hostname (e.g., node-*.cluster-*.nm.internal)
  - target_port: Target port
  - caller_pid: PID of the process that will own the socket
  """
  def tcp_connect(gateway_pid, target_host, target_port, caller_pid) do
    # Timeout must be longer than gen_tcp.connect timeout (10s) to avoid race condition
    GenServer.call(gateway_pid, {:tcp_connect, target_host, target_port, caller_pid}, 15_000)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(cluster_name) do
    # Trap exits so terminate/2 gets called on shutdown
    Process.flag(:trap_exit, true)

    Logger.info("Gateway initializing for cluster #{cluster_name}")

    admin_name = Application.get_env(:edge_admin, :admin_name)

    # Read Netmaker host ID from Metadata (set during init)
    admin_info = Metadata.get_admin()
    netmaker_host_id = admin_info.netmaker_host_id

    # Join VPN network for this cluster using direct API
    # cluster_name is already normalized (e.g., "cluster-default")
    case join_network(cluster_name, netmaker_host_id) do
      :ok ->
        # Register in syn with admin_name to avoid overriding other admins' Gateways
        :syn.register(:cluster_scope, {:gateway, admin_name, cluster_name}, self())
        Logger.debug("Gateway registered in syn for #{admin_name} -> #{cluster_name}")

        Logger.info("Gateway started for cluster #{cluster_name}")

        # Emit telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :connection],
          %{count: 1},
          %{cluster: cluster_name, event: :connected}
        )

        # Emit active count (this will be overwritten by other gateways, but that's ok)
        active_count = length(:syn.members(:cluster_scope, {:gateway, admin_name}))

        :telemetry.execute(
          [:edge_admin, :gateway, :active_count],
          %{active_count: active_count},
          %{}
        )

        {:ok,
         %{
           cluster_name: cluster_name,
           netmaker_host_id: netmaker_host_id,
           admin_name: admin_name,
           joined_at: DateTime.utc_now()
         }}

      {:error, reason} ->
        Logger.error("Failed to initialize Gateway for cluster #{cluster_name}: #{inspect(reason)}")

        {:stop, reason}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Gateway terminating for cluster #{state.cluster_name}, reason: #{inspect(reason)}")

    # Leave the network on shutdown
    leave_network(state.netmaker_host_id, state.cluster_name)

    # Emit telemetry
    :telemetry.execute(
      [:edge_admin, :gateway, :connection],
      %{count: 1},
      %{cluster: state.cluster_name, event: :disconnected}
    )

    :ok
  end

  # ===========================================================================
  # HTTP Client Handlers
  # ===========================================================================

  @impl true
  def handle_call({:scrape_host_metrics, node}, from, state) do
    # Spawn async task to avoid blocking the GenServer
    cluster_name = state.cluster_name

    Task.start(fn ->
      url = "http://#{Node.dns_hostname(node)}:#{node.host_metrics_port}/metrics"

      result =
        case Req.get(url, agent_request_options()) do
          {:ok, %{status: 200, body: metrics_text}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :host, result: :success}
            )

            {:ok, metrics_text}

          {:ok, %{status: status}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :host, result: :error}
            )

            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.error("HTTP request failed: #{inspect(reason)}")

            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :host, result: :error}
            )

            {:error, :service_unavailable}
        end

      # Reply to caller when HTTP request completes
      GenServer.reply(from, result)
    end)

    # Return immediately without replying - task will reply later
    {:noreply, state}
  end

  @impl true
  def handle_call({:scrape_agent_metrics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/v1/agents/metrics/self/raw"

      opts =
        Keyword.merge(
          [auth: {:bearer, node.api_token}],
          agent_request_options()
        )

      result =
        case Req.get(url, opts) do
          {:ok, %{status: 200, body: metrics_text}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :agent, result: :success}
            )

            {:ok, metrics_text}

          {:ok, %{status: status}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :agent, result: :error}
            )

            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.error("HTTP request failed: #{inspect(reason)}")

            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :agent, result: :error}
            )

            {:error, :service_unavailable}
        end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:scrape_wireguard_metrics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      url = "http://#{Node.dns_hostname(node)}:#{node.wireguard_metrics_port}/metrics"

      result =
        case Req.get(url, agent_request_options()) do
          {:ok, %{status: 200, body: metrics_text}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :wireguard, result: :success}
            )

            {:ok, metrics_text}

          {:ok, %{status: status}} ->
            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :wireguard, result: :error}
            )

            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.error("HTTP request failed: #{inspect(reason)}")

            :telemetry.execute(
              [:edge_admin, :gateway, :scrape],
              %{count: 1},
              %{cluster: cluster_name, metrics_type: :wireguard, result: :error}
            )

            {:error, :service_unavailable}
        end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:trigger_self_update, node}, from, state) do
    Task.start(fn ->
      url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/v1/self_updates/trigger"

      opts = Keyword.merge([auth: {:bearer, node.api_token}], agent_request_options())

      result =
        case Req.post(url, opts) do
          {:ok, %{status: 202}} ->
            :ok

          {:ok, %{status: 403}} ->
            {:error, :self_update_disabled}

          {:ok, %{status: status}} ->
            {:error, "HTTP #{status}"}

          {:error, %Req.TransportError{reason: reason} = error} ->
            Logger.debug("HTTP request failed (likely agent restarted): #{inspect(error)}")
            # Treat connection errors as success (watchtower likely restarted the agent)
            if reason in [:timeout, :econnrefused, :closed] do
              :ok
            else
              {:error, error}
            end

          {:error, reason} ->
            Logger.debug("HTTP request failed: #{inspect(reason)}")
            {:error, reason}
        end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:cancel_execution, node, execution_id}, from, state) do
    Task.start(fn ->
      url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/v1/command_executions/#{execution_id}/cancel"

      opts = Keyword.merge([auth: {:bearer, node.api_token}], agent_request_options())

      result =
        case Req.patch(url, opts) do
          {:ok, %{status: status}} when status in 200..299 ->
            :ok

          {:ok, %{status: status}} ->
            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.error("HTTP request failed: #{inspect(reason)}")
            {:error, reason}
        end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:tcp_connect, target_host, target_port, caller_pid}, from, state) do
    Task.start(fn ->
      Logger.debug("Gateway connecting to #{target_host}:#{target_port}")

      result =
        case :gen_tcp.connect(
               String.to_charlist(target_host),
               target_port,
               [:binary, packet: :raw, active: false],
               10_000
             ) do
          {:ok, socket} ->
            Logger.debug("Gateway established connection to #{target_host}:#{target_port}")

            # Check if caller is on same node (local) or different node (remote)
            if node(caller_pid) == node() do
              # Local: transfer socket ownership directly to caller
              :gen_tcp.controlling_process(socket, caller_pid)
              Logger.debug("Socket transferred to local caller")
              {:ok, socket}
            else
              # Remote: spawn proxy process on this node to manage socket
              {:ok, proxy_pid} = RemoteTunnel.start_proxy(socket, caller_pid)
              Logger.debug("Remote proxy started: #{inspect(proxy_pid)}")
              {:ok, :remote, proxy_pid}
            end

          {:error, reason} ->
            Logger.error("Gateway failed to connect to #{target_host}:#{target_port}: #{inspect(reason)}")
            {:error, reason}
        end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  # Handle EXIT messages from linked processes (RemoteTunnel proxies)
  # These are normal when connections close
  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  # Handle unexpected EXIT messages (non-normal termination)
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("Linked process #{inspect(pid)} exited abnormally: #{inspect(reason)}")
    {:noreply, state}
  end

  # Catch-all for unexpected messages
  def handle_info(msg, state) do
    Logger.warning("Gateway received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp join_network(cluster_name, host_id, attempt \\ 1, max_attempts \\ 3) do
    # cluster_name is already normalized (e.g., "cluster-default")
    # Add this host to the cluster network via direct API
    # Netmaker handles DNS automatically (no custom DNS entries needed)
    case Vpn.add_host_to_network(host_id, cluster_name) do
      {:ok, _node} ->
        # Verify that we actually joined the network
        case verify_joined_network(host_id, cluster_name) do
          :ok ->
            Logger.info("Gateway joined network #{cluster_name} (verified)")
            :ok

          {:error, :not_found} ->
            Logger.warning(
              "Gateway join API succeeded but verification failed for #{cluster_name} (attempt #{attempt}/#{max_attempts})"
            )

            if attempt < max_attempts do
              # Exponential backoff: 500ms, 1000ms, 2000ms
              delay_ms = trunc(500 * :math.pow(2, attempt - 1))
              Logger.info("Retrying join for #{cluster_name} in #{delay_ms}ms...")
              :timer.sleep(delay_ms)
              join_network(cluster_name, host_id, attempt + 1, max_attempts)
            else
              Logger.error("Failed to verify join for #{cluster_name} after #{max_attempts} attempts")

              {:error, :join_verification_failed}
            end

          {:error, reason} ->
            Logger.error("Failed to verify join for #{cluster_name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to join network #{cluster_name}: #{inspect(reason)} (attempt #{attempt}/#{max_attempts})"
        )

        if attempt < max_attempts do
          # Exponential backoff: 500ms, 1000ms, 2000ms
          delay_ms = trunc(500 * :math.pow(2, attempt - 1))
          Logger.info("Retrying join for #{cluster_name} in #{delay_ms}ms...")
          :timer.sleep(delay_ms)
          join_network(cluster_name, host_id, attempt + 1, max_attempts)
        else
          Logger.error("Failed to join network #{cluster_name} after #{max_attempts} attempts")
          {:error, reason}
        end
    end
  end

  defp leave_network(netmaker_host_id, cluster_name, attempt \\ 1, max_attempts \\ 3) do
    case Vpn.remove_host_from_network(netmaker_host_id, cluster_name) do
      {:ok, _} ->
        # Verify that we actually left the network
        case verify_left_network(netmaker_host_id, cluster_name) do
          :ok ->
            Logger.info("Gateway left network #{cluster_name} (verified)")
            :ok

          {:error, :still_present} ->
            Logger.warning(
              "Gateway leave API succeeded but node still present in #{cluster_name} (attempt #{attempt}/#{max_attempts})"
            )

            if attempt < max_attempts do
              # Exponential backoff: 500ms, 1000ms, 2000ms
              delay_ms = trunc(500 * :math.pow(2, attempt - 1))
              Logger.info("Retrying leave for #{cluster_name} in #{delay_ms}ms...")
              :timer.sleep(delay_ms)
              leave_network(netmaker_host_id, cluster_name, attempt + 1, max_attempts)
            else
              Logger.error(
                "Node still present in #{cluster_name} after #{max_attempts} leave attempts - may require manual cleanup"
              )

              # Don't crash terminate - just log and continue
              :ok
            end

          {:error, reason} ->
            Logger.warning("Failed to verify leave for #{cluster_name}: #{inspect(reason)} - assuming success")

            # Don't crash terminate on verification errors
            :ok
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to leave network #{cluster_name}: #{inspect(reason)} (attempt #{attempt}/#{max_attempts})"
        )

        if attempt < max_attempts do
          # Exponential backoff: 500ms, 1000ms, 2000ms
          delay_ms = trunc(500 * :math.pow(2, attempt - 1))
          Logger.info("Retrying leave for #{cluster_name} in #{delay_ms}ms...")
          :timer.sleep(delay_ms)
          leave_network(netmaker_host_id, cluster_name, attempt + 1, max_attempts)
        else
          Logger.error(
            "Failed to leave network #{cluster_name} after #{max_attempts} attempts - may require manual cleanup"
          )

          # Don't crash terminate - just log and continue
          :ok
        end
    end
  end

  defp verify_joined_network(host_id, cluster_name) do
    # Wait briefly for Netmaker to process the operation
    :timer.sleep(500)

    # Check if our host has a node in this network
    case Vpn.list_nodes(cluster_name) do
      {:ok, nodes} ->
        node_exists =
          Enum.any?(nodes, fn node ->
            node["hostid"] == host_id
          end)

        if node_exists do
          Logger.debug("Verified: host #{host_id} found in network #{cluster_name}")
          :ok
        else
          Logger.debug("Verification failed: host #{host_id} not found in network #{cluster_name}")
          {:error, :not_found}
        end

      {:error, reason} ->
        Logger.error("Failed to list nodes for verification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verify_left_network(host_id, cluster_name) do
    # Wait briefly for Netmaker to process the operation
    :timer.sleep(500)

    # Check if our host still has a node in this network
    case Vpn.list_nodes(cluster_name) do
      {:ok, nodes} ->
        node_still_exists =
          Enum.any?(nodes, fn node ->
            node["hostid"] == host_id
          end)

        if node_still_exists do
          Logger.debug("Verification failed: host #{host_id} still present in network #{cluster_name}")

          {:error, :still_present}
        else
          Logger.debug("Verified: host #{host_id} removed from network #{cluster_name}")
          :ok
        end

      {:error, :not_found} ->
        # Network doesn't exist anymore - that's fine, we're definitely not in it
        Logger.debug("Network #{cluster_name} not found - assuming successful leave")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to list nodes for leave verification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
