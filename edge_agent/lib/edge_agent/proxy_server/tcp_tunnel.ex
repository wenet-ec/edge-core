# edge_agent/lib/edge_agent/proxy_server/tcp_tunnel.ex
defmodule EdgeAgent.ProxyServer.TcpTunnel do
  @moduledoc """
  Bidirectional TCP tunnel for agent proxy forwarding.

  Agent version is simpler than admin - no Gateway routing needed.
  Directly connects to target and forwards data in both directions.
  """

  require Logger

  @doc """
  Connect to target host and start bidirectional forwarding.

  Optional initial_data parameter allows sending data immediately after
  connection (useful for HTTP requests).

  Returns {:ok, target_socket} on success, {:error, reason} on failure.
  """
  def connect_and_forward(client_socket, target_host, target_port, initial_data \\ nil) do
    case connect_to_target(target_host, target_port) do
      {:ok, target_socket} ->
        # Send initial data if provided (for HTTP requests)
        if initial_data do
          :gen_tcp.send(target_socket, initial_data)
        end

        # Spawn bidirectional forwarding process
        forwarder_pid =
          spawn_link(fn ->
            forward_loop(client_socket, target_socket)
          end)

        # Transfer client socket ownership to forwarder
        :gen_tcp.controlling_process(client_socket, forwarder_pid)

        # Spawn reverse forwarding
        spawn_link(fn -> forward_loop(target_socket, client_socket) end)

        {:ok, target_socket}

      {:error, reason} = error ->
        Logger.error("Failed to connect to #{target_host}:#{target_port}: #{inspect(reason)}")
        error
    end
  end

  # Connect to target host using gen_tcp
  defp connect_to_target(target_host, target_port) do
    target_host_charlist = String.to_charlist(target_host)

    case :gen_tcp.connect(
           target_host_charlist,
           target_port,
           [:binary, packet: :raw, active: false],
           30_000
         ) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Forwarding loop: recv from source, send to destination
  defp forward_loop(source_socket, dest_socket) do
    case :gen_tcp.recv(source_socket, 0) do
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
