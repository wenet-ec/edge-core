# edge_admin/lib/edge_admin/edge_clusters/gateway.ex
defmodule EdgeAdmin.EdgeClusters.Gateway do
  @moduledoc """
  Gateway process for managing admin's connection to an edge cluster network.

  One Gateway process runs per cluster assigned to this admin. The Gateway:
  - Joins the cluster's VPN network using direct API (no enrollment keys)
  - Registers in syn for cross-admin routing
  - Provides HTTP client functions for communicating with agents

  ## VPN Lifecycle

  - **Join**: Uses Vpn.add_host_to_network (direct API, no enrollment key)
  - **Leave**: Uses Vpn.remove_host_from_network (removes Node, preserves Host)

  ## Cross-Admin Routing

  Registered in syn with key `{:gateway, cluster_id}` for cross-admin routing.
  Other admins can route requests to this Gateway via:

      :syn.whereis(:cluster_scope, {:gateway, cluster_id})

  ## HTTP Client Functions

  - execute_command/3 - Send command to agent
  - scrape_metrics/2 - Scrape metrics from node exporter
  - trigger_self_update/2 - Trigger self-update on agent
  """

  use GenServer
  require Logger

  alias EdgeAdmin.Vpn

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
  Sends a command execution request to an agent.

  ## Parameters

  - gateway_pid: Gateway process (via syn lookup or direct pid)
  - node: Node struct with dns_hostname, http_port, api_token
  - execution_data: Map with command execution details

  ## Returns

  - {:ok, :sent} - Command sent successfully
  - {:error, reason} - HTTP error or network failure
  """
  def execute_command(gateway_pid, node, execution_data) do
    GenServer.call(gateway_pid, {:execute_command, node, execution_data}, 30_000)
  end

  @doc """
  Scrapes metrics from a node's exporter.

  ## Parameters

  - gateway_pid: Gateway process
  - node: Node struct with dns_hostname, metrics_port

  ## Returns

  - {:ok, metrics_text} - Raw Prometheus metrics
  - {:error, reason} - HTTP error or network failure
  """
  def scrape_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_metrics, node}, 30_000)
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

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(cluster_name) do
    # Trap exits so terminate/2 gets called on shutdown
    Process.flag(:trap_exit, true)

    Logger.info("Gateway initializing for cluster #{cluster_name}")

    admin_name = Application.get_env(:edge_admin, :admin_name)

    # Read Netmaker host ID from ETS (set by Metadata during init)
    [{:admin, admin_info}] = :ets.lookup(:metadata, :admin)
    netmaker_host_id = admin_info.netmaker_host_id

    # Join VPN network for this cluster using direct API
    # cluster_name is already normalized (e.g., "cluster-default")
    case join_network(cluster_name, netmaker_host_id) do
      :ok ->
        # Register in syn with admin_name to avoid overriding other admins' Gateways
        :syn.register(:cluster_scope, {:gateway, admin_name, cluster_name}, self())
        Logger.debug("Gateway registered in syn for #{admin_name} -> #{cluster_name}")

        Logger.info("Gateway started for cluster #{cluster_name}")

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
    Logger.info(
      "Gateway terminating for cluster #{state.cluster_name}, reason: #{inspect(reason)}"
    )

    # Leave the network on shutdown
    leave_network(state.netmaker_host_id, state.cluster_name)

    :ok
  end

  # ===========================================================================
  # HTTP Client Handlers
  # ===========================================================================

  @impl true
  def handle_call({:execute_command, node, execution_data}, _from, state) do
    url = "http://#{node.dns_hostname}:#{node.http_port}/api/command_executions"

    case Req.post(url,
      json: execution_data,
      auth: {:bearer, node.api_token},
      receive_timeout: 5000,
      retry: false
    ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:reply, {:ok, :sent}, state}

      {:ok, %{status: status}} ->
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:scrape_metrics, node}, _from, state) do
    url = "http://#{node.dns_hostname}:#{node.metrics_port}/metrics"

    case Req.get(url, retry: false) do
      {:ok, %{status: 200, body: metrics_text}} ->
        {:reply, {:ok, metrics_text}, state}

      {:ok, %{status: status}} ->
        {:reply, {:error, "HTTP #{status}"}, state}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:trigger_self_update, node}, _from, state) do
    url = "http://#{node.dns_hostname}:#{node.http_port}/api/self_updates/"

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
        :ok  # Don't crash on cleanup failure
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
