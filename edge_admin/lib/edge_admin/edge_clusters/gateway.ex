# edge_admin/lib/edge_admin/edge_clusters/gateway.ex
defmodule EdgeAdmin.EdgeClusters.Gateway do
  @moduledoc """
  Gateway process for managing admin's connection to an edge cluster network.

  One Gateway process runs per cluster assigned to this admin. The Gateway:
  - Joins the cluster's VPN network using direct API (no enrollment keys)
  - Registers in syn for cross-admin routing
  - Provides HTTP client functions for admin-to-agent communication

  ## VPN Lifecycle

  - **Join**: Uses Vpn.add_host_to_network (direct API, no enrollment key)
  - **Leave**: Uses Vpn.remove_host_from_network (removes Node, preserves Host)

  ## Cross-Admin Routing

  Registered in syn with key `{:gateway, admin_name, cluster_name}` for cross-admin routing.
  Other admins can route requests to this Gateway via:

      :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_name})

  ## HTTP Client Functions

  - scrape_metrics/2 - Scrape metrics from node exporter
  - trigger_self_update/2 - Trigger self-update on agent
  """

  use GenServer
  require Logger

  alias EdgeAdmin.Vpn
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.ProxyServers.RemoteTunnel

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
          :undefined -> {:error, :gateway_not_found}
          {pid, _metadata} -> {:ok, pid}
        end
    end
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
    GenServer.call(gateway_pid, {:scrape_host_metrics, node}, 30_000)
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
    GenServer.call(gateway_pid, {:scrape_agent_metrics, node}, 30_000)
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
    GenServer.call(gateway_pid, {:scrape_wireguard_metrics, node}, 30_000)
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
    GenServer.call(gateway_pid, {:trigger_self_update, node}, 30_000)
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
    GenServer.call(gateway_pid, {:cancel_execution, node, execution_id}, 30_000)
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
    GenServer.call(gateway_pid, {:tcp_connect, target_host, target_port, caller_pid}, 30_000)
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
        Logger.error(
          "Failed to initialize Gateway for cluster #{cluster_name}: #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "Gateway terminating for cluster #{state.cluster_name}, reason: #{inspect(reason)}"
    )

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
  def handle_call({:scrape_host_metrics, node}, _from, state) do
    url = "http://#{Node.dns_hostname(node)}:#{node.host_metrics_port}/metrics"

    result = case Req.get(url, retry: false) do
      {:ok, %{status: 200, body: metrics_text}} ->
        # Emit success telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :host, result: :success}
        )
        {:reply, {:ok, metrics_text}, state}

      {:ok, %{status: status}} ->
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :host, result: :error}
        )
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :host, result: :error}
        )
        {:reply, {:error, :service_unavailable}, state}
    end

    result
  end

  @impl true
  def handle_call({:scrape_agent_metrics, node}, _from, state) do
    url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/agents/metrics/self/raw"

    result = case Req.get(url, auth: {:bearer, node.api_token}, retry: false) do
      {:ok, %{status: 200, body: metrics_text}} ->
        # Emit success telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :agent, result: :success}
        )
        {:reply, {:ok, metrics_text}, state}

      {:ok, %{status: status}} ->
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :agent, result: :error}
        )
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :agent, result: :error}
        )
        {:reply, {:error, :service_unavailable}, state}
    end

    result
  end

  @impl true
  def handle_call({:scrape_wireguard_metrics, node}, _from, state) do
    url = "http://#{Node.dns_hostname(node)}:#{node.wireguard_metrics_port}/metrics"

    result = case Req.get(url, retry: false) do
      {:ok, %{status: 200, body: metrics_text}} ->
        # Emit success telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :wireguard, result: :success}
        )
        {:reply, {:ok, metrics_text}, state}

      {:ok, %{status: status}} ->
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :wireguard, result: :error}
        )
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        # Emit error telemetry
        :telemetry.execute(
          [:edge_admin, :gateway, :scrape],
          %{count: 1},
          %{cluster: state.cluster_name, metrics_type: :wireguard, result: :error}
        )
        {:reply, {:error, :service_unavailable}, state}
    end

    result
  end

  @impl true
  def handle_call({:trigger_self_update, node}, _from, state) do
    url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/self_updates/"

    case Req.post(url,
           auth: {:bearer, node.api_token},
           receive_timeout: 5000,
           retry: false
         ) do
      {:ok, %{status: 200}} ->
        {:reply, :ok, state}

      {:ok, %{status: status}} ->
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:cancel_execution, node, execution_id}, _from, state) do
    url = "http://#{Node.dns_hostname(node)}:#{node.http_port}/api/command_executions/#{execution_id}/cancel"

    case Req.patch(url,
           auth: {:bearer, node.api_token},
           receive_timeout: 5000,
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:reply, :ok, state}

      {:ok, %{status: status}} ->
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:tcp_connect, target_host, target_port, caller_pid}, _from, state) do
    Logger.debug("Gateway connecting to #{target_host}:#{target_port}")

    # Connect through this Gateway's VPN interface
    case :gen_tcp.connect(
           String.to_charlist(target_host),
           target_port,
           [:binary, packet: :raw, active: false],
           30_000
         ) do
      {:ok, socket} ->
        Logger.debug("Gateway established connection to #{target_host}:#{target_port}")

        # Check if caller is on same node (local) or different node (remote)
        if node(caller_pid) == node() do
          # Local: transfer socket ownership directly to caller
          :gen_tcp.controlling_process(socket, caller_pid)
          Logger.debug("Socket transferred to local caller")
          {:reply, {:ok, socket}, state}
        else
          # Remote: spawn proxy process on this node to manage socket
          {:ok, proxy_pid} = RemoteTunnel.start_proxy(socket, caller_pid)
          Logger.debug("Remote proxy started: #{inspect(proxy_pid)}")
          {:reply, {:ok, :remote, proxy_pid}, state}
        end

      {:error, reason} ->
        Logger.error("Gateway failed to connect to #{target_host}:#{target_port}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
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

  defp join_network(cluster_name, host_id) do
    # cluster_name is already normalized (e.g., "cluster-default")
    # Add this host to the cluster network via direct API
    # Netmaker handles DNS automatically (no custom DNS entries needed)
    case Vpn.add_host_to_network(host_id, cluster_name) do
      {:ok, _node} ->
        Logger.info("Gateway joined network #{cluster_name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to join network #{cluster_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp leave_network(netmaker_host_id, cluster_name) do
    case Vpn.remove_host_from_network(netmaker_host_id, cluster_name) do
      {:ok, _} ->
        # Wait for actual deletion (Netmaker uses PendingDelete + zombie cleanup)
        case wait_for_deletion(netmaker_host_id, cluster_name) do
          :ok ->
            Logger.info("Gateway left network #{cluster_name}")

          {:error, :timeout} ->
            Logger.warning(
              "Gateway left network #{cluster_name} but deletion still pending after 10s"
            )
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to leave network #{cluster_name}: #{inspect(reason)}")
        # Don't crash on cleanup failure
        :ok
    end
  end

  defp wait_for_deletion(netmaker_host_id, cluster_name, max_attempts \\ 10, delay_ms \\ 1000) do
    Enum.reduce_while(1..max_attempts, {:error, :timeout}, fn attempt, _acc ->
      case check_if_still_in_network(netmaker_host_id, cluster_name) do
        {:ok, false} ->
          # Node actually deleted from network
          Logger.debug(
            "Node deletion confirmed for #{cluster_name} after #{attempt * delay_ms}ms"
          )

          {:halt, :ok}

        {:ok, true} ->
          # Still exists (or PendingDelete=true)
          if attempt < max_attempts do
            :timer.sleep(delay_ms)
            {:cont, {:error, :timeout}}
          else
            {:halt, {:error, :timeout}}
          end

        {:error, reason} ->
          # Couldn't check - log and continue
          Logger.debug("Failed to check deletion status: #{inspect(reason)}")

          if attempt < max_attempts do
            :timer.sleep(delay_ms)
            {:cont, {:error, :timeout}}
          else
            {:halt, {:error, :timeout}}
          end
      end
    end)
  end

  defp check_if_still_in_network(netmaker_host_id, cluster_name) do
    # Check if this host still has a node in the network
    case Vpn.list_nodes(cluster_name) do
      {:ok, nodes} ->
        # Check if any node belongs to this host
        still_exists =
          Enum.any?(nodes, fn node ->
            node["hostid"] == netmaker_host_id
          end)

        {:ok, still_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
