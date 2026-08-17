# edge_admin/lib/edge_admin/proxy_servers/admin_tunnel/session.ex
defmodule EdgeAdmin.ProxyServers.AdminTunnel.Session do
  @moduledoc "Authenticates and relays one Admin-to-Admin proxy tunnel."

  alias EdgeAdmin.ProxyServers.AdminTunnel.Config
  alias EdgeAdmin.ProxyServers.AdminTunnel.Protocol
  alias EdgeAdmin.ProxyServers.Config, as: ProxyConfig
  alias EdgeAdmin.ProxyServers.Transport.Forwarder

  require Logger

  def start(socket) do
    pid =
      spawn(fn ->
        receive do
          :start -> run(socket)
        end
      end)

    :gen_tcp.controlling_process(socket, pid)
    send(pid, :start)
    {:ok, pid}
  end

  defp run(socket) do
    case read_request(socket) do
      {:ok, target_host, target_port} ->
        case :gen_tcp.connect(
               String.to_charlist(target_host),
               target_port,
               [:binary, packet: :raw, active: false],
               ProxyConfig.connection_timeout()
             ) do
          {:ok, target_socket} ->
            :ok = :gen_tcp.send(socket, Protocol.response(:ok))
            Forwarder.forward(socket, target_socket, %{transport: :admin_tcp_tunnel, target_host: target_host})

          {:error, reason} ->
            Logger.debug("Admin proxy tunnel target connection failed: #{inspect(reason)}")
            reject(socket)
        end

      {:error, reason} ->
        Logger.debug("Admin proxy tunnel handshake rejected: #{inspect(reason)}")
        reject(socket)
    end
  after
    :gen_tcp.close(socket)
  end

  defp read_request(socket) do
    with {:ok, magic} <- recv_exact(socket, byte_size("EDGE_TUNNEL")),
         {:ok, version} <- recv_exact(socket, 1),
         {:ok, host_size} <- recv_exact(socket, 2),
         {:ok, rest} <- recv_exact(socket, :binary.decode_unsigned(host_size) + 2 + 32) do
      Protocol.validate_handshake(Config.secret(), magic <> version <> host_size <> rest)
    end
  end

  defp recv_exact(socket, length), do: :gen_tcp.recv(socket, length, ProxyConfig.handshake_timeout())

  defp reject(socket) do
    _ = :gen_tcp.send(socket, Protocol.response({:error, :rejected}))
    :gen_tcp.close(socket)
  end
end
