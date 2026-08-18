# edge_admin/lib/edge_admin_proxy/edge_admin_proxy.ex
defmodule EdgeAdminProxy do
  @moduledoc """
  HTTP and SOCKS5 forward proxy servers for admin access to edge nodes.

  Runs two Ranch listeners providing proxy access to the VPN network, allowing
  users to route traffic through the admin to reach edge nodes.

  ## Routing Modes

  The routing mode is selected per-connection by the proxy username.

  ### Direct (admin as exit)
  - Username: `_` or empty string
  - Admin routes traffic through the VPN Gateway directly to the target
  - Used only for reaching nodes on the VPN mesh from the admin
  - Non-VPN targets are rejected

  ### Chained (agent as exit)
  - Username: a node's DNS hostname, e.g. `node-<id>.cluster-<name>.nm.internal`
  - Admin tunnels through the named agent, which then connects to the target
  - Client → Admin → Agent → target
  - Useful for exiting from the agent's network/IP

  ## Listeners

  - **HTTP Forward Proxy**: Port 43128 (configurable via `HTTP_PROXY_PORT`)
  - **SOCKS5 Proxy**: Port 41080 (configurable via `SOCKS5_PROXY_PORT`)

  Authentication (both listeners):
  - **Username**: `_` / empty for direct, node DNS hostname for chaining
  - **Password**: `PROXY_KEY` env (falls back to `MASTER_KEY`)

  ## Architecture

  - **GenServer**: Manages lifecycle of both Ranch listeners
  - **Ranch Listeners**: One for HTTP, one for SOCKS5
  - **Protocol Handlers**: `Http.Handler` and `Socks5.Handler`
  - **Gateway Integration**: VPN-bound traffic routes through cluster Gateway
    GenServers. In direct mode, both HTTP and SOCKS5 require VPN hostnames.
    Reaching arbitrary internet/LAN targets is only supported through
    proxy chaining via an agent.

  """

  use GenServer

  alias EdgeAdminProxy.Config
  alias EdgeAdminProxy.Http.Handler, as: HttpHandler
  alias EdgeAdminProxy.Socks5.Handler, as: Socks5Handler
  alias EdgeAdminProxy.Transport.TunnelRegistry

  require Logger

  @listener_retry_interval 2_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if the proxy GenServer has finished its `init/1` callback.

  Returns `false` if the process is missing or the call times out (1s).
  Used by health checks.
  """
  def initialized? do
    case Process.whereis(__MODULE__) do
      nil ->
        false

      pid ->
        try do
          GenServer.call(pid, :initialized?, 1000)
        catch
          :exit, _ -> false
        end
    end
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    http_port = Config.http_proxy_port()
    socks5_port = Config.socks5_proxy_port()
    listen_address = Config.listen_address()

    state = %{
      http_listener_ref: nil,
      socks5_listener_ref: nil,
      http_port: http_port,
      socks5_port: socks5_port,
      listen_address: listen_address,
      initialized: false
    }

    case start_listeners(state) do
      {:ok, new_state} ->
        Logger.info("Admin proxy servers started successfully")
        Logger.info("  HTTP proxy: #{format_ip(listen_address)}:#{http_port}")
        Logger.info("  SOCKS5 proxy: #{format_ip(listen_address)}:#{socks5_port}")
        {:ok, %{new_state | initialized: true}}

      {:error, reason, new_state} ->
        Logger.warning("Failed to start proxy servers: #{inspect(reason)}; retrying")
        schedule_listener_retry()
        {:ok, %{new_state | initialized: true}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  @impl true
  def handle_info(:retry_listener_start, %{http_listener_ref: nil, socks5_listener_ref: nil} = state) do
    case start_listeners(state) do
      {:ok, new_state} ->
        Logger.info("Admin proxy servers recovered")
        {:noreply, new_state}

      {:error, reason, new_state} ->
        Logger.warning("Admin proxy servers are still unavailable: #{inspect(reason)}; retrying")
        schedule_listener_retry()
        {:noreply, new_state}
    end
  end

  def handle_info(:retry_listener_start, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down admin proxy servers...")
    stop_listeners(state)
    drain_tunnels()
    :ok
  end

  # Graceful drain: stop accepting connections (done above), signal all live
  # tunnel handlers to wind down, wait up to the grace window, then force-close.
  defp drain_tunnels do
    grace = Config.drain_grace_timeout()
    signaled = TunnelRegistry.drain(grace)

    if signaled > 0 do
      Logger.info("Draining #{signaled} active proxy tunnel(s), grace #{grace}ms")

      case TunnelRegistry.wait_for_empty(grace) do
        :ok ->
          Logger.info("All proxy tunnels drained cleanly")

        {:timeout, remaining} ->
          closed = TunnelRegistry.force_close()
          Logger.warning("Drain timed out with #{remaining} tunnel(s); force-closed #{closed}")
      end
    end

    :ok
  end

  defp start_listeners(state) do
    case start_http_proxy(state) do
      {:ok, http_ref} ->
        case start_socks5_proxy(state) do
          {:ok, socks5_ref} ->
            {:ok,
             %{
               state
               | http_listener_ref: http_ref,
                 socks5_listener_ref: socks5_ref
             }}

          {:error, reason} ->
            :ranch.stop_listener(http_ref)
            {:error, reason, %{state | http_listener_ref: nil, socks5_listener_ref: nil}}
        end

      {:error, reason} ->
        {:error, reason, %{state | http_listener_ref: nil, socks5_listener_ref: nil}}
    end
  end

  defp schedule_listener_retry do
    Process.send_after(self(), :retry_listener_start, @listener_retry_interval)
  end

  defp start_http_proxy(state) do
    transport_opts = %{
      socket_opts:
        Config.listen_socket_options() ++
          [
            {:ip, state.listen_address},
            {:port, state.http_port}
          ],
      num_acceptors: Config.num_acceptors()
    }

    case :ranch.start_listener(
           :admin_http_proxy,
           :ranch_tcp,
           transport_opts,
           HttpHandler,
           []
         ) do
      {:ok, _pid} ->
        Logger.info("HTTP proxy listener started on port #{state.http_port}")
        {:ok, :admin_http_proxy}

      {:error, reason} ->
        Logger.error("Failed to start HTTP proxy listener: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_socks5_proxy(state) do
    transport_opts = %{
      socket_opts:
        Config.listen_socket_options() ++
          [
            {:ip, state.listen_address},
            {:port, state.socks5_port}
          ],
      num_acceptors: Config.num_acceptors()
    }

    case :ranch.start_listener(
           :admin_socks5_proxy,
           :ranch_tcp,
           transport_opts,
           Socks5Handler,
           []
         ) do
      {:ok, _pid} ->
        Logger.info("SOCKS5 proxy listener started on port #{state.socks5_port}")
        {:ok, :admin_socks5_proxy}

      {:error, reason} ->
        Logger.error("Failed to start SOCKS5 proxy listener: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stop_listeners(state) do
    if state.http_listener_ref do
      :ranch.stop_listener(:admin_http_proxy)
      Logger.info("HTTP proxy stopped")
    end

    if state.socks5_listener_ref do
      :ranch.stop_listener(:admin_socks5_proxy)
      Logger.info("SOCKS5 proxy stopped")
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> List.to_string()
end
