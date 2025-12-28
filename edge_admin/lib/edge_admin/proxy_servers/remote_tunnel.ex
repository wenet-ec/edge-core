# edge_admin/lib/edge_admin/proxy_servers/remote_tunnel.ex
defmodule EdgeAdmin.ProxyServers.RemoteTunnel do
  @moduledoc """
  Manages remote TCP tunnels when Gateway is on a different Erlang node.

  When the Gateway process is on a different node, we can't transfer socket
  ownership directly. Instead, we spawn a proxy process on the Gateway node
  that owns the socket and forwards data via messages.
  """

  alias EdgeAdmin.ProxyServers.Config

  require Logger

  @doc """
  Starts a remote tunnel proxy process on the Gateway node.

  This process will:
  - Own the target socket
  - Forward data from target to caller via messages
  - Receive data from caller and send to target
  """
  def start_proxy(target_socket, caller_pid) do
    pid = spawn_link(__MODULE__, :proxy_loop, [target_socket, caller_pid])
    :gen_tcp.controlling_process(target_socket, pid)
    {:ok, pid}
  end

  @doc """
  Proxy loop that handles bidirectional forwarding via messages.
  """
  def proxy_loop(target_socket, caller_pid) do
    :inet.setopts(target_socket, active: true)

    receive do
      # Data from target socket -> forward to caller
      {:tcp, ^target_socket, data} ->
        send(caller_pid, {:remote_target_data, self(), data})
        proxy_loop(target_socket, caller_pid)

      # Target socket closed -> notify caller
      {:tcp_closed, ^target_socket} ->
        send(caller_pid, {:remote_target_closed, self()})
        :ok

      # Target socket error -> notify caller
      {:tcp_error, ^target_socket, reason} ->
        send(caller_pid, {:remote_target_error, self(), reason})
        :ok

      # Data from caller -> send to target
      {:send_to_target, data} ->
        :gen_tcp.send(target_socket, data)
        proxy_loop(target_socket, caller_pid)

      # Consume HTTP response (for HTTP proxy chaining)
      {:consume_http_response, reply_to} ->
        result = consume_http_response(target_socket)
        send(reply_to, {:http_response_consumed, self(), result})
        proxy_loop(target_socket, caller_pid)

      # Consume SOCKS5 response (for SOCKS5 proxy chaining)
      {:consume_socks5_response, reply_to} ->
        result = consume_socks5_response(target_socket)
        send(reply_to, {:socks5_response_consumed, self(), result})
        proxy_loop(target_socket, caller_pid)

      # Close from caller
      :close ->
        :gen_tcp.close(target_socket)
        :ok
    end
  end

  # Consume HTTP response headers from socket
  defp consume_http_response(socket, buffer \\ "") do
    receive do
      {:tcp, ^socket, data} ->
        new_buffer = buffer <> data

        if String.contains?(new_buffer, "\r\n\r\n") do
          if String.contains?(new_buffer, "200") do
            {:ok, :accepted}
          else
            {:error, :rejected}
          end
        else
          consume_http_response(socket, new_buffer)
        end

      {:tcp_closed, ^socket} ->
        {:error, :closed}

      {:tcp_error, ^socket, reason} ->
        {:error, reason}
    after
      Config.connection_timeout() ->
        {:error, :timeout}
    end
  end

  # Consume SOCKS5 handshake responses from socket
  defp consume_socks5_response(socket) do
    # SOCKS5 handshake has 3 responses:
    # 1. Auth method selection (2 bytes)
    # 2. Auth result (2 bytes)
    # 3. Connect result (10 bytes for domain type)

    with {:ok, _auth_method_response} <- recv_socks5_data(socket, 2),
         {:ok, auth_result} <- recv_socks5_data(socket, 2),
         :ok <- validate_socks5_auth(auth_result),
         {:ok, connect_response} <- recv_socks5_data(socket, 10),
         :ok <- validate_socks5_connect(connect_response) do
      {:ok, :accepted}
    end
  end

  defp recv_socks5_data(socket, bytes) do
    receive do
      {:tcp, ^socket, data} when byte_size(data) >= bytes ->
        {:ok, data}

      {:tcp, ^socket, _data} ->
        {:error, :invalid_response}

      {:tcp_closed, ^socket} ->
        {:error, :closed}

      {:tcp_error, ^socket, reason} ->
        {:error, reason}
    after
      Config.connection_timeout() ->
        {:error, :timeout}
    end
  end

  defp validate_socks5_auth(<<1, 0>>), do: :ok
  defp validate_socks5_auth(_), do: {:error, :auth_failed}

  defp validate_socks5_connect(<<5, 0, _::binary>>), do: :ok
  defp validate_socks5_connect(_), do: {:error, :connect_failed}
end
