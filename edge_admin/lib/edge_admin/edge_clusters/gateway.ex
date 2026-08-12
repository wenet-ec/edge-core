# edge_admin/lib/edge_admin/edge_clusters/gateway.ex
defmodule EdgeAdmin.EdgeClusters.Gateway do
  @moduledoc """
  Gateway GenServer managing VPN connection and HTTP communication with an edge cluster.

  One Gateway process runs per cluster assigned to this admin. Each Gateway maintains
  a direct host-to-network VPN membership for that cluster and registers itself
  in `:cluster_scope` so other admins can route cluster-specific work to the
  owner.

  Note: command-execution *delivery* (`AgentClient.deliver_execution/2`) does
  NOT go through Gateway — `Commands` calls `AgentClient` directly. Only the
  cancel path routes through Gateway, because cancellation needs to find the
  owning admin's process via syn.

  ## Cross-Admin Routing

  Gateways register in syn to enable distributed request routing. The owning
  admin's pid is looked up via the `:cluster_scope` registry; once obtained,
  callers issue `GenServer.call/3` against it over Erlang distribution.

  ## VPN Lifecycle

  - **Join**: `Vpn.add_host_to_network(host_id, network_name)` - Direct API call
  - **Leave**: `Vpn.remove_host_from_network(host_id, network_name)` - Removes node, keeps host
  - **No Enrollment Keys**: Uses existing host credentials from admin cluster
  """

  use GenServer

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.AgentClient
  alias EdgeAdmin.ProxyServers.Tunnel.RemoteTunnel
  alias EdgeAdmin.Vpn

  require Logger

  defp tcp_connect_timeout,
    do: :edge_admin |> Application.get_env(:proxy_timeouts, []) |> Keyword.get(:connection, 5_000)

  defp telemetry_result({:ok, _}), do: :success
  defp telemetry_result(_), do: :error

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

  If ownership changed between the Metadata read and the syn lookup (TOCTOU
  during topology recomputation), falls back to scanning every known admin's
  registration in `:cluster_scope` to locate the gateway.

  Returns `{:ok, gateway_pid}`, `{:error, :gateway_not_found}`, or
  `{:error, :no_owner}`.
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

  @doc "Scrapes host metrics from a node's Node Exporter."
  def scrape_host_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_host_metrics, node}, AgentClient.metrics_call_timeout())
  end

  @doc "Scrapes agent application metrics from a node's PromEx endpoint."
  def scrape_agent_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_agent_metrics, node}, AgentClient.metrics_call_timeout())
  end

  @doc "Scrapes WireGuard metrics from a node's WireGuard Exporter endpoint."
  def scrape_wireguard_metrics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:scrape_wireguard_metrics, node}, AgentClient.metrics_call_timeout())
  end

  @doc """
  Retrieves an Agent self-diagnostic report.
  """
  def get_diagnostics(gateway_pid, node) do
    GenServer.call(gateway_pid, {:get_diagnostics, node}, AgentClient.diagnostics_call_timeout())
  end

  @doc "Triggers self-update on an agent."
  def trigger_self_update(gateway_pid, node) do
    GenServer.call(gateway_pid, {:trigger_self_update, node}, AgentClient.command_call_timeout())
  end

  @doc "Cancels a command execution on an agent."
  def cancel_execution(gateway_pid, node, execution_id) do
    GenServer.call(gateway_pid, {:cancel_execution, node, execution_id}, AgentClient.command_call_timeout())
  end

  @doc """
  Establishes TCP connection to a target through the Gateway's VPN.

  Gateway is a pure network abstraction - it only handles VPN connectivity.

  ## Returns

  Two success shapes depending on where `caller_pid` lives:

  - `{:ok, socket}` — `caller_pid` is on the same Erlang node as the Gateway.
    The socket's controlling process is transferred to `caller_pid`; the
    caller owns it from that point on.
  - `{:ok, :remote, proxy_pid}` — `caller_pid` is on a different Erlang node.
    Erlang distribution can't transfer socket ownership across nodes, so a
    `RemoteTunnel` proxy process is spawned on the Gateway's node to own the
    socket and forward bytes to/from `caller_pid`.
  - `{:error, reason}` — `:gen_tcp.connect/4` failed.

  The caller is responsible for:
  - Managing the returned socket (or proxy pid)
  - Setting up any streaming/forwarding logic

  - target_host: VPN DNS hostname (e.g., node-*.cluster-*.nm.internal)
  - target_port: Target port
  - caller_pid: PID of the process that will own the socket
  """
  def tcp_connect(gateway_pid, target_host, target_port, caller_pid) do
    # GenServer timeout must exceed the gen_tcp.connect timeout inside handle_call
    GenServer.call(gateway_pid, {:tcp_connect, target_host, target_port, caller_pid}, tcp_connect_timeout() + 2_000)
  end

  @impl true
  def init(cluster_name) do
    Process.flag(:trap_exit, true)

    Logger.info("Gateway initializing for cluster #{cluster_name}")

    admin_name = Application.get_env(:edge_admin, :admin_name)

    admin_info = Metadata.get_admin()
    vpn_host_id = admin_info.vpn_host_id

    case join_network(cluster_name, vpn_host_id) do
      :ok ->
        :syn.register(:cluster_scope, {:gateway, admin_name, cluster_name}, self())
        Logger.debug("Gateway registered in syn for #{admin_name} -> #{cluster_name}")

        Logger.info("Gateway started for cluster #{cluster_name}")

        :telemetry.execute(
          [:edge_admin, :gateway, :connection],
          %{count: 1},
          %{cluster: cluster_name, event: :connected}
        )

        {:ok,
         %{
           cluster_name: cluster_name,
           vpn_host_id: vpn_host_id,
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

    leave_network(state.vpn_host_id, state.cluster_name)

    :telemetry.execute(
      [:edge_admin, :gateway, :connection],
      %{count: 1},
      %{cluster: state.cluster_name, event: :disconnected}
    )

    :ok
  end

  @impl true
  def handle_call({:scrape_host_metrics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      result = AgentClient.scrape_host_metrics(node)

      :telemetry.execute(
        [:edge_admin, :gateway, :scrape],
        %{count: 1},
        %{cluster: cluster_name, metrics_type: :host, result: telemetry_result(result)}
      )

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:scrape_agent_metrics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      result = AgentClient.scrape_agent_metrics(node)

      :telemetry.execute(
        [:edge_admin, :gateway, :scrape],
        %{count: 1},
        %{cluster: cluster_name, metrics_type: :agent, result: telemetry_result(result)}
      )

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:scrape_wireguard_metrics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      result = AgentClient.scrape_wireguard_metrics(node)

      :telemetry.execute(
        [:edge_admin, :gateway, :scrape],
        %{count: 1},
        %{cluster: cluster_name, metrics_type: :wireguard, result: telemetry_result(result)}
      )

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_diagnostics, node}, from, state) do
    cluster_name = state.cluster_name

    Task.start(fn ->
      result = AgentClient.get_diagnostics(node)

      :telemetry.execute(
        [:edge_admin, :gateway, :diagnostics],
        %{count: 1},
        %{cluster: cluster_name, result: telemetry_result(result)}
      )

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:trigger_self_update, node}, from, state) do
    Task.start(fn ->
      GenServer.reply(from, AgentClient.trigger_self_update(node))
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:cancel_execution, node, execution_id}, from, state) do
    Task.start(fn ->
      GenServer.reply(from, AgentClient.cancel_execution(node, execution_id))
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
               tcp_connect_timeout()
             ) do
          {:ok, socket} ->
            Logger.debug("Gateway established connection to #{target_host}:#{target_port}")

            if node(caller_pid) == node() do
              :gen_tcp.controlling_process(socket, caller_pid)
              Logger.debug("Socket transferred to local caller")
              {:ok, socket}
            else
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

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("Linked process #{inspect(pid)} exited abnormally: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("Gateway received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp join_network(cluster_name, host_id, attempt \\ 1, max_attempts \\ 3) do
    case Vpn.add_host_to_network(host_id, cluster_name) do
      {:ok, :already_joined} ->
        # Edge VPN returns HTTP 500 "host already part of network" for this.
        Logger.info("Gateway already in network #{cluster_name}, skipping join")
        :ok

      {:ok, _} ->
        case verify_joined_network(host_id, cluster_name) do
          :ok ->
            Logger.info("Gateway joined network #{cluster_name} (verified)")
            :ok

          {:error, :not_found} ->
            Logger.warning(
              "Gateway join API succeeded but verification failed for #{cluster_name} (attempt #{attempt}/#{max_attempts})"
            )

            if attempt < max_attempts do
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

  defp leave_network(vpn_host_id, cluster_name, attempt \\ 1, max_attempts \\ 3) do
    case Vpn.remove_host_from_network(vpn_host_id, cluster_name) do
      {:ok, _} ->
        case verify_left_network(vpn_host_id, cluster_name) do
          :ok ->
            Logger.info("Gateway left network #{cluster_name} (verified)")
            :ok

          {:error, :still_present} ->
            Logger.warning(
              "Gateway leave API succeeded but node still present in #{cluster_name} (attempt #{attempt}/#{max_attempts})"
            )

            if attempt < max_attempts do
              delay_ms = trunc(500 * :math.pow(2, attempt - 1))
              Logger.info("Retrying leave for #{cluster_name} in #{delay_ms}ms...")
              :timer.sleep(delay_ms)
              leave_network(vpn_host_id, cluster_name, attempt + 1, max_attempts)
            else
              Logger.error(
                "Node still present in #{cluster_name} after #{max_attempts} leave attempts - may require manual cleanup"
              )

              :ok
            end

          {:error, reason} ->
            Logger.warning("Failed to verify leave for #{cluster_name}: #{inspect(reason)} - assuming success")

            :ok
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to leave network #{cluster_name}: #{inspect(reason)} (attempt #{attempt}/#{max_attempts})"
        )

        if attempt < max_attempts do
          delay_ms = trunc(500 * :math.pow(2, attempt - 1))
          Logger.info("Retrying leave for #{cluster_name} in #{delay_ms}ms...")
          :timer.sleep(delay_ms)
          leave_network(vpn_host_id, cluster_name, attempt + 1, max_attempts)
        else
          Logger.error(
            "Failed to leave network #{cluster_name} after #{max_attempts} attempts - may require manual cleanup"
          )

          :ok
        end
    end
  end

  defp verify_joined_network(host_id, cluster_name) do
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
        Logger.debug("Network #{cluster_name} not found - assuming successful leave")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to list nodes for leave verification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
