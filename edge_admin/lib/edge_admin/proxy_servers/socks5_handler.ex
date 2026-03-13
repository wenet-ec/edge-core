# edge_admin/lib/edge_admin/proxy_servers/socks5_handler.ex
defmodule EdgeAdmin.ProxyServers.Socks5Handler do
  @moduledoc """
  Ranch protocol handler for SOCKS5 proxy.

  SOCKS5 Protocol Flow:
  1. Client greeting: version + auth methods
  2. Server response: version + selected auth method
  3. Auth negotiation (username/password)
  4. Connection request: target host + port
  5. Server response: success/failure
  6. Bidirectional TCP tunnel

  Reference: RFC 1928 (SOCKS5), RFC 1929 (Username/Password Auth)
  """

  @behaviour :ranch_protocol

  alias EdgeAdmin.ProxyServers.Authentication
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler
  alias EdgeAdmin.ProxyServers.TcpTunnel

  require Logger

  # SOCKS5 constants
  @socks_version 5
  @auth_method_username_password 2

  @cmd_connect 1
  @atyp_ipv4 1
  @atyp_domain 3
  @atyp_ipv6 4

  @impl true
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  def init(ref, transport, _opts) do
    {:ok, socket} = :ranch.handshake(ref)
    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    Logger.info("SOCKS5 client connected from #{:inet.ntoa(client_ip)}:#{client_port}")

    start_time = System.monotonic_time()
    result = handle_socks5_handshake(socket, transport)
    duration_ms = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    case result do
      {:ok, routing_mode, proxy_mode, cluster_name} ->
        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          %{
            protocol: :socks5,
            result: :success,
            routing_mode: routing_mode,
            proxy_mode: proxy_mode,
            cluster: cluster_name
          }
        )

        :telemetry.execute(
          [:edge_admin, :proxy, :session, :duration],
          %{duration: duration_ms},
          %{protocol: :socks5, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
        )

        :ok

      {:error, :auth_failed} ->
        :telemetry.execute(
          [:edge_admin, :proxy, :auth_failure],
          %{count: 1, total: 1},
          %{protocol: :socks5}
        )

        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          %{protocol: :socks5, result: :auth_failed, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"}
        )

        transport.close(socket)

      {:error, reason} ->
        _error_category = ErrorHandler.log_error(reason, %{protocol: :socks5})

        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          reason
          |> ErrorHandler.telemetry_metadata(:socks5)
          |> Map.merge(%{result: :failure, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"})
        )

        transport.close(socket)
    end
  end

  # Returns {:ok, routing_mode, proxy_mode, cluster_name} | {:error, reason}
  defp handle_socks5_handshake(socket, transport) do
    with {:ok, methods} <- read_greeting(socket, transport),
         :ok <- send_auth_method(socket, transport, methods),
         {:ok, routing_mode, exit_node} <- handle_authentication(socket, transport),
         {:ok, target_host, target_port} <- read_connect_request(socket, transport) do
      establish_tunnel(socket, transport, target_host, target_port, routing_mode, exit_node)
    end
  end

  # Step 1: Read client greeting
  defp read_greeting(socket, transport) do
    case transport.recv(socket, 2, Config.read_timeout()) do
      {:ok, <<@socks_version, nmethods>>} ->
        case transport.recv(socket, nmethods, Config.read_timeout()) do
          {:ok, methods} -> {:ok, :binary.bin_to_list(methods)}
          {:error, reason} -> {:error, reason}
        end

      {:ok, <<version, _nmethods>>} ->
        Logger.warning("Unsupported SOCKS version: #{version}")
        {:error, :unsupported_version}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Step 2: Send selected auth method
  defp send_auth_method(socket, transport, client_methods) do
    if @auth_method_username_password in client_methods do
      response = <<@socks_version, @auth_method_username_password>>
      transport.send(socket, response)
    else
      # Client doesn't support authentication - reject
      Logger.warning("SOCKS5 client doesn't support username/password authentication (method 2)")
      response = <<@socks_version, 0xFF>>
      transport.send(socket, response)
      {:error, :no_acceptable_methods}
    end
  end

  # Step 3: Username/Password authentication (RFC 1929)
  defp handle_authentication(socket, transport) do
    case transport.recv(socket, 2, Config.read_timeout()) do
      {:ok, <<1, ulen>>} ->
        with {:ok, username_bin} <- transport.recv(socket, ulen, Config.read_timeout()),
             {:ok, <<plen>>} <- transport.recv(socket, 1, Config.read_timeout()),
             {:ok, password_bin} <- transport.recv(socket, plen, Config.read_timeout()) do
          username = to_string(username_bin)
          password = to_string(password_bin)

          case Authentication.authenticate_and_parse(username, password) do
            {:ok, :direct} ->
              send_auth_success(socket, transport)
              {:ok, :direct, nil}

            {:ok, :chain, node} ->
              send_auth_success(socket, transport)
              {:ok, :chain, node}

            {:error, _reason} ->
              send_auth_failure(socket, transport)
              {:error, :auth_failed}
          end
        end

      {:ok, <<version, _ulen>>} ->
        Logger.warning("Unsupported auth version: #{version}")
        send_auth_failure(socket, transport)
        {:error, :unsupported_auth_version}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_auth_success(socket, transport) do
    response = <<1, 0>>
    transport.send(socket, response)
  end

  defp send_auth_failure(socket, transport) do
    response = <<1, 1>>
    transport.send(socket, response)
  end

  # Step 4: Read connection request
  defp read_connect_request(socket, transport) do
    case transport.recv(socket, 4, Config.read_timeout()) do
      {:ok, <<@socks_version, @cmd_connect, 0, atyp>>} ->
        read_destination_address(socket, transport, atyp)

      {:ok, <<@socks_version, cmd, 0, _atyp>>} ->
        Logger.warning("Unsupported SOCKS5 command: #{cmd}")
        # Command not supported
        send_reply(socket, transport, 7, "0.0.0.0", 0)
        {:error, :unsupported_command}

      {:ok, <<version, _cmd, _rsv, _atyp>>} ->
        Logger.warning("Unsupported SOCKS version: #{version}")
        {:error, :unsupported_version}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_destination_address(socket, transport, @atyp_ipv4) do
    case transport.recv(socket, 6, Config.read_timeout()) do
      {:ok, <<a, b, c, d, port::16>>} ->
        host = "#{a}.#{b}.#{c}.#{d}"
        {:ok, host, port}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_destination_address(socket, transport, @atyp_domain) do
    case transport.recv(socket, 1, Config.read_timeout()) do
      {:ok, <<domain_len>>} ->
        case transport.recv(socket, domain_len + 2, Config.read_timeout()) do
          {:ok, data} ->
            <<domain_bin::binary-size(domain_len), port::16>> = data
            host = to_string(domain_bin)
            {:ok, host, port}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_destination_address(socket, transport, @atyp_ipv6) do
    case transport.recv(socket, 18, Config.read_timeout()) do
      {:ok, <<ipv6::binary-size(16), port::16>>} ->
        # Format IPv6 address as colon-separated hex groups
        <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> = ipv6

        host =
          Enum.map_join(
            [a, b, c, d, e, f, g, h],
            ":",
            &(&1 |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
          )

        {:ok, host, port}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_destination_address(socket, transport, atyp) do
    Logger.warning("Unsupported address type: #{atyp}")
    # Address type not supported
    send_reply(socket, transport, 8, "0.0.0.0", 0)
    {:error, :unsupported_address_type}
  end

  # Step 5: Establish tunnel
  # Returns {:ok, routing_mode, proxy_mode, cluster_name} | {:error, reason}
  defp establish_tunnel(socket, transport, target_host, target_port, routing_mode, exit_node) do
    opts = build_tunnel_opts(routing_mode, exit_node)
    proxy_mode = if routing_mode == :chain, do: :chain, else: :direct
    cluster_name = TcpTunnel.cluster_name_from_hostname(target_host) || "unknown"

    case TcpTunnel.connect_and_forward(socket, target_host, target_port, self(), nil, opts) do
      {:ok, :local, _target_socket} ->
        send_reply(socket, transport, 0, target_host, target_port)
        :timer.sleep(:infinity)
        {:ok, :local, proxy_mode, cluster_name}

      {:ok, :remote, proxy_pid} ->
        send_reply(socket, transport, 0, target_host, target_port)
        transport.setopts(socket, active: true)
        handle_remote_streaming(socket, transport, proxy_pid)
        {:ok, :remote, proxy_mode, cluster_name}

      {:error, reason} ->
        reply_code = ErrorHandler.socks5_reply_code(reason)
        send_reply(socket, transport, reply_code, target_host, target_port)
        {:error, reason}
    end
  end

  defp build_tunnel_opts(:direct, _exit_node), do: []
  defp build_tunnel_opts(:chain, exit_node), do: [exit_node: exit_node, protocol: :socks5]

  # Handle remote streaming (message-based via RemoteTunnel proxy)
  defp handle_remote_streaming(socket, transport, proxy_pid) do
    receive do
      {:tcp, ^socket, data} ->
        send(proxy_pid, {:send_to_target, data})
        handle_remote_streaming(socket, transport, proxy_pid)

      {:remote_target_data, ^proxy_pid, data} ->
        transport.send(socket, data)
        handle_remote_streaming(socket, transport, proxy_pid)

      {:remote_target_closed, ^proxy_pid} ->
        transport.close(socket)
        {:ok, :closed}

      {:remote_target_error, ^proxy_pid, _reason} ->
        transport.close(socket)
        {:ok, :closed}

      {:tcp_closed, ^socket} ->
        send(proxy_pid, :close)
        {:ok, :closed}

      {:tcp_error, ^socket, _reason} ->
        send(proxy_pid, :close)
        {:ok, :closed}
    end
  end

  # Send SOCKS5 reply
  defp send_reply(socket, transport, reply_code, _host, _port) do
    # For simplicity, always return IPv4 0.0.0.0:0 as bind address
    response = <<@socks_version, reply_code, 0, @atyp_ipv4, 0, 0, 0, 0, 0::16>>
    transport.send(socket, response)
  end
end
