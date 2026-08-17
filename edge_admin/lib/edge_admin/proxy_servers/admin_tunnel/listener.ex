# edge_admin/lib/edge_admin/proxy_servers/admin_tunnel/listener.ex
defmodule EdgeAdmin.ProxyServers.AdminTunnel.Listener do
  @moduledoc "Accepts authenticated Admin-to-Admin proxy data connections."

  use GenServer

  alias EdgeAdmin.ProxyServers.AdminTunnel.Config
  alias EdgeAdmin.ProxyServers.AdminTunnel.Session

  require Logger

  @bind_retry_interval 2_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, %{listen_sockets: []}, {:continue, :bind}}
  end

  @impl true
  def handle_continue(:bind, state) do
    {:noreply, bind_or_retry(state)}
  end

  @impl true
  def handle_info(:retry_bind, %{listen_sockets: []} = state) do
    {:noreply, bind_or_retry(state)}
  end

  def handle_info(:retry_bind, state), do: {:noreply, state}

  defp bind_or_retry(state) do
    case Config.bind_addresses() do
      {:ok, addresses} ->
        sockets = Enum.flat_map(addresses, &listen/1)

        if sockets == [] do
          Logger.warning("Admin proxy tunnel has no bindable Admin-cluster address; retrying")
          schedule_bind_retry()
          state
        else
          Logger.info("Admin proxy tunnel started on #{length(sockets)} Admin-cluster address(es)")
          Enum.each(sockets, fn socket -> spawn_link(fn -> accept_loop(socket) end) end)
          %{state | listen_sockets: sockets}
        end

      {:error, reason} ->
        Logger.warning("Admin proxy tunnel cannot resolve its Admin-cluster address (#{inspect(reason)}); retrying")
        schedule_bind_retry()
        state
    end
  end

  defp schedule_bind_retry do
    Process.send_after(self(), :retry_bind, @bind_retry_interval)
  end

  defp listen({family, bind_address}) do
    options =
      maybe_ipv6_only([:binary, family, {:ip, bind_address}, packet: :raw, active: false, reuseaddr: true], family)

    case :gen_tcp.listen(Config.port(), options) do
      {:ok, socket} ->
        Logger.info("Admin proxy tunnel bound to #{format_address(bind_address)}:#{Config.port()}")
        [socket]

      {:error, reason} ->
        Logger.warning("Could not bind Admin proxy tunnel to #{format_address(bind_address)}: #{inspect(reason)}")
        []
    end
  end

  defp maybe_ipv6_only(options, :inet6), do: [{:ipv6_v6only, true} | options]
  defp maybe_ipv6_only(options, :inet), do: options

  defp format_address(address), do: address |> :inet.ntoa() |> List.to_string()

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Session.start(socket)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("Admin proxy tunnel accept failed: #{inspect(reason)}")
        Process.sleep(1_000)
        accept_loop(listen_socket)
    end
  end

  @impl true
  def terminate(_reason, %{listen_sockets: sockets}) do
    Enum.each(sockets, &:gen_tcp.close/1)
    :ok
  end
end
