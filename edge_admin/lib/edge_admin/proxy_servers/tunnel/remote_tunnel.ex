# edge_admin/lib/edge_admin/proxy_servers/tunnel/remote_tunnel.ex
defmodule EdgeAdmin.ProxyServers.Tunnel.RemoteTunnel do
  @moduledoc """
  Manages remote TCP tunnels when Gateway is on a different Erlang node.

  When the Gateway process is on a different node, we can't transfer socket
  ownership directly. Instead, we spawn a proxy process on the Gateway node
  that owns the socket and forwards data via messages.

  Handshake-response consumption (HTTP `CONNECT` reply, SOCKS5 method/auth/
  connect replies) uses the pure `Socks5Codec` parsers with a `BufferedReader`
  over the active-mode mailbox — both tolerate fragmented TCP deliveries.
  """

  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.Socks5.Codec, as: Socks5Codec
  alias EdgeAdmin.ProxyServers.Transport.BufferedReader

  require Logger

  @doc """
  Starts a remote tunnel proxy process on the Gateway node.
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
      {:tcp, ^target_socket, data} ->
        send(caller_pid, {:remote_target_data, self(), data})
        proxy_loop(target_socket, caller_pid)

      {:tcp_closed, ^target_socket} ->
        send(caller_pid, {:remote_target_closed, self()})
        :ok

      {:tcp_error, ^target_socket, reason} ->
        send(caller_pid, {:remote_target_error, self(), reason})
        :ok

      {:send_to_target, data} ->
        :gen_tcp.send(target_socket, data)
        proxy_loop(target_socket, caller_pid)

      {:consume_http_response, reply_to} ->
        result = consume_http_response(target_socket)
        send(reply_to, {:http_response_consumed, self(), result})
        proxy_loop(target_socket, caller_pid)

      {:consume_socks5_response, reply_to} ->
        result = consume_socks5_response(target_socket)
        send(reply_to, {:socks5_response_consumed, self(), result})
        proxy_loop(target_socket, caller_pid)

      :close ->
        :gen_tcp.close(target_socket)
        :ok
    end
  end

  # Read an HTTP status line + headers via the active mailbox, look for 2xx.
  defp consume_http_response(socket) do
    parser = fn buf ->
      case :binary.split(buf, "\r\n\r\n") do
        [_headers, _rest] ->
          case parse_http_status_line(buf) do
            {:ok, status} when status >= 200 and status < 300 -> {:ok, :accepted, <<>>}
            {:ok, status} -> {:error, {:http_status, status}}
            :error -> {:error, :bad_response}
          end

        [_] ->
          {:need_more, 0}
      end
    end

    case BufferedReader.read_active(socket, parser, Config.handshake_timeout()) do
      {:ok, :accepted, _rest} -> {:ok, :accepted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_http_status_line(<<"HTTP/1.", _v, " ", code::binary-size(3), _rest::binary>>) do
    case Integer.parse(code) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_http_status_line(_), do: :error

  # SOCKS5 upstream-proxy handshake has 3 replies:
  #   1. Method selection reply (2 bytes)
  #   2. Auth status reply        (2 bytes)
  #   3. Connect reply            (variable by ATYP)
  defp consume_socks5_response(socket) do
    timeout = Config.handshake_timeout()

    with {:ok, method, leftover_a} <-
           BufferedReader.read_active(socket, &Socks5Codec.parse_method_reply/1, timeout),
         :ok <- validate_method(method),
         {:ok, auth_status, leftover_b} <-
           read_active_with_leftover(socket, &Socks5Codec.parse_auth_response/1, timeout, leftover_a),
         :ok <- validate_auth(auth_status),
         {:ok, {rep, _bnd_host, _bnd_port}, _leftover_c} <-
           read_active_with_leftover(socket, &Socks5Codec.parse_reply/1, timeout, leftover_b),
         :ok <- validate_connect(rep) do
      {:ok, :accepted}
    else
      {:error, _} = err -> err
    end
  end

  defp read_active_with_leftover(socket, parser, timeout, leftover) do
    case parser.(leftover) do
      {:ok, _, _} = ok -> ok
      {:error, _} = err -> err
      {:need_more, _} -> collect(socket, parser, timeout, leftover)
    end
  end

  defp collect(socket, parser, timeout, buf) do
    receive do
      {:tcp, ^socket, data} ->
        new = buf <> data

        case parser.(new) do
          {:ok, _, _} = ok -> ok
          {:error, _} = err -> err
          {:need_more, _} -> collect(socket, parser, timeout, new)
        end

      {:tcp_closed, ^socket} ->
        {:error, :closed}

      {:tcp_error, ^socket, reason} ->
        {:error, reason}
    after
      timeout -> {:error, :timeout}
    end
  end

  # Accept any method the server picked that we can satisfy (no-auth or user/pass).
  defp validate_method(0), do: :ok
  defp validate_method(2), do: :ok
  defp validate_method(0xFF), do: {:error, :no_acceptable_methods}
  defp validate_method(m), do: {:error, {:unsupported_method, m}}

  defp validate_auth(0), do: :ok
  defp validate_auth(_), do: {:error, :socks5_auth_failed}

  defp validate_connect(0), do: :ok
  defp validate_connect(code), do: {:error, {:socks5_connect, code}}
end
