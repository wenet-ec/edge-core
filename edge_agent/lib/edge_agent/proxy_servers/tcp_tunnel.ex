# edge_agent/lib/edge_agent/proxy_server/tcp_tunnel.ex
defmodule EdgeAgent.ProxyServers.TcpTunnel do
  @moduledoc """
  Bidirectional TCP tunnel for agent proxy forwarding.

  Agent version is simpler than admin - no Gateway routing needed.
  Directly connects to target and forwards data in both directions.
  """

  alias EdgeAgent.ProxyServers.Config
  alias EdgeAgent.ProxyServers.ErrorHandler

  require Logger

  @doc """
  Connect to target and start bidirectional forwarding.

  Accepts a pre-resolved IP tuple (from DestinationValidator.resolve_and_validate/2)
  or a hostname string. Passing an IP tuple skips DNS resolution entirely, closing
  the DNS rebinding window.

  Optional initial_data is sent to the target immediately after connection
  (useful for HTTP requests).

  Returns {:ok, target_socket} on success, {:error, reason} on failure.
  """
  def connect_and_forward(client_socket, target, target_port, initial_data \\ nil) do
    case connect_to_target(target, target_port) do
      {:ok, target_socket} ->
        if initial_data do
          :gen_tcp.send(target_socket, initial_data)
        end

        forward(client_socket, target_socket)
        {:ok, target_socket}

      {:error, reason} = error ->
        ErrorHandler.log_error(reason, %{
          target: target,
          target_port: target_port
        })

        error
    end
  end

  @doc """
  Connect to a target host or IP tuple.

  Accepts either a hostname string (DNS resolved by :gen_tcp) or a pre-resolved
  IP tuple {a, b, c, d}. Use the IP tuple form when you want to guarantee no
  second DNS resolution after validation.

  Returns {:ok, socket} or {:error, reason}.
  """
  def connect_to_target(target, target_port) do
    connect_arg =
      case target do
        {_, _, _, _} = ip_tuple -> ip_tuple
        host when is_binary(host) -> String.to_charlist(host)
      end

    case :gen_tcp.connect(
           connect_arg,
           target_port,
           [:binary, packet: :raw, active: false],
           Config.connection_timeout()
         ) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Set up bidirectional forwarding between two already-connected sockets.

  Transfers client_socket ownership to the forwarder process. Call this
  only after any response (e.g. HTTP 200) has been sent on client_socket,
  since ownership is transferred immediately.
  """
  def forward(client_socket, target_socket) do
    forwarder_pid =
      spawn_link(fn ->
        forward_loop(client_socket, target_socket)
      end)

    :gen_tcp.controlling_process(client_socket, forwarder_pid)

    spawn_link(fn -> forward_loop(target_socket, client_socket) end)

    :ok
  end

  # Forwarding loop: recv from source, send to destination.
  # recv_timeout closes half-open connections where the peer disappeared without
  # a proper TCP close (NAT timeout, process kill, network cut).
  defp forward_loop(source_socket, dest_socket) do
    case :gen_tcp.recv(source_socket, 0, Config.recv_timeout()) do
      {:ok, data} ->
        case :gen_tcp.send(dest_socket, data) do
          :ok ->
            forward_loop(source_socket, dest_socket)

          {:error, _reason} ->
            cleanup_sockets(source_socket, dest_socket)
        end

      {:error, _reason} ->
        cleanup_sockets(source_socket, dest_socket)
    end
  end

  defp cleanup_sockets(socket1, socket2) do
    :gen_tcp.close(socket1)
    :gen_tcp.close(socket2)
  end
end
