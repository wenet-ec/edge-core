# edge_agent/lib/edge_agent_proxy/edge_agent_proxy.ex
defmodule EdgeAgentProxy do
  @moduledoc """
  Proxy servers supervisor managing HTTP and SOCKS5 forward proxies.

  Runs two separate Ranch listeners:
  - HTTP forward proxy on port 43128 (configurable via `AGENT_HTTP_PROXY_PORT`)
  - SOCKS5 proxy on port 41080 (configurable via `AGENT_SOCKS5_PROXY_PORT`)

  Both proxies use simple authentication:
  - Username: "_" (underscore)
  - Password: `proxy_password` from the settings table

  When `PROXY_SERVERS_AUTH_ENABLED=false` (default `true`), credentials are
  not verified and any client is accepted. Intended for local dev only.

  No cluster awareness: the agent proxies any destination accepted by the
  SSRF/destination allowlist (see `Transport.DestinationValidator`). It does
  not resolve cluster membership or route based on it.
  """

  use GenServer

  alias EdgeAgentProxy.Config
  alias EdgeAgentProxy.Http.Handler, as: HttpHandler
  alias EdgeAgentProxy.Socks5.Handler, as: Socks5Handler
  alias EdgeAgentProxy.Transport.TunnelRegistry

  require Logger

  @listener_retry_interval 2_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if the proxy GenServer has finished its `init/1` callback.

  This only confirms `init/1` returned, not that the Ranch listeners
  are actually accepting connections — listener-startup errors are logged
  and retried in the background without blocking the GenServer from coming
  up. Use `status/0` for a liveness signal that reflects the actual listeners.
  Returns `false` if the process is missing or the call times out (1s).
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

  @doc """
  Returns the listener status:

  - `:running` — both Ranch listeners are accepting connections
  - `:error` — one or both listeners failed to start; background retries
    continue until both listeners recover
  - `:not_started` — the GenServer process is missing
  - `:unknown` — call timed out

  Used by health checks where `initialized?/0` is too lenient.
  """
  @spec status() :: :running | :error | :not_started | :unknown
  def status do
    case Process.whereis(__MODULE__) do
      nil ->
        :not_started

      pid ->
        try do
          GenServer.call(pid, :status, 1000)
        catch
          :exit, _ -> :unknown
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
      initialized: false,
      status: :error
    }

    case start_listeners(state) do
      {:ok, new_state} ->
        Logger.info("Proxy servers started successfully")
        Logger.info("  HTTP proxy: #{format_ip(listen_address)}:#{http_port}")
        Logger.info("  SOCKS5 proxy: #{format_ip(listen_address)}:#{socks5_port}")
        {:ok, %{new_state | initialized: true, status: :running}}

      {:error, reason, new_state} ->
        Logger.warning("Failed to start proxy servers: #{inspect(reason)}; retrying")
        schedule_listener_retry()
        {:ok, %{new_state | initialized: true, status: :error}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, Map.get(state, :status, :error), state}
  end

  @impl true
  def handle_info(:retry_listener_start, %{http_listener_ref: nil, socks5_listener_ref: nil} = state) do
    case start_listeners(state) do
      {:ok, new_state} ->
        Logger.info("Proxy servers recovered")
        {:noreply, %{new_state | status: :running}}

      {:error, reason, new_state} ->
        Logger.warning("Proxy servers are still unavailable: #{inspect(reason)}; retrying")
        schedule_listener_retry()
        {:noreply, new_state}
    end
  end

  def handle_info(:retry_listener_start, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down proxy servers...")
    stop_listeners(state)
    drain_tunnels()
    :ok
  end

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
           :http_proxy,
           :ranch_tcp,
           transport_opts,
           HttpHandler,
           []
         ) do
      {:ok, _pid} ->
        Logger.info("HTTP proxy listener started on port #{state.http_port}")
        {:ok, :http_proxy}

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
           :socks5_proxy,
           :ranch_tcp,
           transport_opts,
           Socks5Handler,
           []
         ) do
      {:ok, _pid} ->
        Logger.info("SOCKS5 proxy listener started on port #{state.socks5_port}")
        {:ok, :socks5_proxy}

      {:error, reason} ->
        Logger.error("Failed to start SOCKS5 proxy listener: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stop_listeners(state) do
    if state.http_listener_ref do
      :ranch.stop_listener(:http_proxy)
      Logger.info("HTTP proxy stopped")
    end

    if state.socks5_listener_ref do
      :ranch.stop_listener(:socks5_proxy)
      Logger.info("SOCKS5 proxy stopped")
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> List.to_string()
end
