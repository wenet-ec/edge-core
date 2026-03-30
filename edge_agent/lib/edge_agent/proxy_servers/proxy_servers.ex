# edge_agent/lib/edge_agent/proxy_servers.ex
defmodule EdgeAgent.ProxyServers do
  @moduledoc """
  Proxy servers supervisor managing HTTP and SOCKS5 forward proxies.

  Runs two separate Ranch listeners:
  - HTTP forward proxy on port 44880 (configurable)
  - SOCKS5 proxy on port 44180 (configurable)

  Both proxies use simple authentication:
  - Username: "_" (underscore)
  - Password: proxy_password from settings table

  Pure TCP passthrough - no cluster awareness or routing logic.
  """

  use GenServer

  alias EdgeAgent.ProxyServers.Config

  require Logger

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

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

  def servers_status do
    GenServer.call(__MODULE__, :servers_status, 5_000)
  catch
    :exit, {:noproc, _} -> :not_started
    :exit, {:timeout, _} -> :unknown
  end

  # GenServer callbacks
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
      status: :stopped,
      initialized: false
    }

    case start_proxy_servers(state) do
      {:ok, new_state} ->
        Logger.info("Proxy servers started successfully")
        Logger.info("  HTTP proxy: #{format_ip(listen_address)}:#{http_port}")
        Logger.info("  SOCKS5 proxy: #{format_ip(listen_address)}:#{socks5_port}")
        {:ok, %{new_state | initialized: true}}

      {:error, reason, new_state} ->
        Logger.error("Failed to start proxy servers: #{inspect(reason)}")
        {:ok, %{new_state | initialized: true}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  @impl true
  def handle_call(:servers_status, _from, state) do
    status =
      if state.http_listener_ref && state.socks5_listener_ref do
        :running
      else
        :stopped
      end

    {:reply, status, %{state | status: status}}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Shutting down proxy servers...")
    stop_proxy_servers(state)
    :ok
  end

  # Private functions

  defp start_proxy_servers(state) do
    with {:ok, http_ref} <- start_http_proxy(state),
         {:ok, socks5_ref} <- start_socks5_proxy(state) do
      {:ok,
       %{
         state
         | http_listener_ref: http_ref,
           socks5_listener_ref: socks5_ref,
           status: :running
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to start proxy servers: #{inspect(reason)}")
        {:error, reason, %{state | status: :error}}
    end
  end

  defp start_http_proxy(state) do
    transport_opts = %{
      socket_opts: [
        {:ip, state.listen_address},
        {:port, state.http_port}
      ],
      num_acceptors: Config.num_acceptors()
    }

    case :ranch.start_listener(
           :http_proxy,
           :ranch_tcp,
           transport_opts,
           EdgeAgent.ProxyServers.HttpHandler,
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
      socket_opts: [
        {:ip, state.listen_address},
        {:port, state.socks5_port}
      ],
      num_acceptors: Config.num_acceptors()
    }

    case :ranch.start_listener(
           :socks5_proxy,
           :ranch_tcp,
           transport_opts,
           EdgeAgent.ProxyServers.Socks5Handler,
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

  defp stop_proxy_servers(state) do
    if state.http_listener_ref do
      :ranch.stop_listener(:http_proxy)
      Logger.info("HTTP proxy stopped")
    end

    if state.socks5_listener_ref do
      :ranch.stop_listener(:socks5_proxy)
      Logger.info("SOCKS5 proxy stopped")
    end
  end

  # Helper to format IP tuple for logging
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_binary(ip), do: ip
end
