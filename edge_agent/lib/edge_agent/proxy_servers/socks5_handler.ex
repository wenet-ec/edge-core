# edge_agent/lib/edge_agent/proxy_server/socks5_handler.ex
defmodule EdgeAgent.ProxyServers.Socks5Handler do
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

  alias EdgeAgent.ProxyServers.Authentication
  alias EdgeAgent.ProxyServers.Config
  alias EdgeAgent.ProxyServers.DestinationValidator
  alias EdgeAgent.ProxyServers.ErrorHandler
  alias EdgeAgent.ProxyServers.TcpTunnel

  require Logger

  # SOCKS5 constants
  @socks_version 5
  @auth_method_username_password 2

  @cmd_connect 1
  @atyp_ipv4 1
  @atyp_domain 3
  @atyp_ipv6 4

  @reply_success 0
  @reply_command_not_supported 7
  @reply_address_type_not_supported 8

  @impl true
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  def init(ref, transport, _opts) do
    {:ok, socket} = :ranch.handshake(ref)
    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    Logger.info("SOCKS5 client connected from #{:inet.ntoa(client_ip)}:#{client_port}")

    start_time = System.monotonic_time(:millisecond)

    result =
      case handle_socks5_handshake(socket, transport) do
        :ok ->
          :ok

        {:error, reason} ->
          _error_category = ErrorHandler.log_error(reason, %{protocol: :socks5})
          transport.close(socket)
          {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    # Emit connection telemetry
    {conn_result, telemetry_meta} =
      case result do
        :ok ->
          {:success, %{result: :success, protocol: :socks5}}

        {:error, :auth_failed} ->
          {:auth_failed, %{result: :auth_failed, protocol: :socks5}}

        {:error, reason} ->
          {:failure, reason |> ErrorHandler.telemetry_metadata(:socks5) |> Map.put(:result, :failure)}
      end

    :telemetry.execute(
      [:edge_agent, :proxy, :socks5, :connection],
      %{count: 1, total: 1},
      telemetry_meta
    )

    # Emit session duration telemetry if connection was successful
    if conn_result == :success do
      :telemetry.execute(
        [:edge_agent, :proxy, :session, :duration],
        %{duration: duration},
        %{protocol: :socks5}
      )
    end

    result
  end

  defp handle_socks5_handshake(socket, transport) do
    with {:ok, methods} <- read_greeting(socket, transport),
         :ok <- send_auth_method(socket, transport, methods),
         :ok <- handle_authentication(socket, transport),
         {:ok, target_host, target_port} <- read_connect_request(socket, transport),
         {:ok, _target_socket} <- establish_tunnel(socket, transport, target_host, target_port) do
      # Tunnel is active, keep handler alive
      :timer.sleep(:infinity)
    end
  end

  # Step 1: Read client greeting
  # +----+----------+----------+
  # |VER | NMETHODS | METHODS  |
  # +----+----------+----------+
  # | 1  |    1     | 1 to 255 |
  # +----+----------+----------+
  defp read_greeting(socket, transport) do
    case transport.recv(socket, 2, Config.read_timeout()) do
      {:ok, <<@socks_version, nmethods>>} ->
        case transport.recv(socket, nmethods, Config.read_timeout()) do
          {:ok, methods} ->
            {:ok, :binary.bin_to_list(methods)}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, <<version, _nmethods>>} ->
        Logger.warning("Unsupported SOCKS version: #{version}")
        {:error, :unsupported_version}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Step 2: Send selected auth method
  # +----+--------+
  # |VER | METHOD |
  # +----+--------+
  # | 1  |   1    |
  # +----+--------+
  defp send_auth_method(socket, transport, client_methods) do
    # Authentication is ALWAYS required - only accept username/password method
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
  # Client request:
  # +----+------+----------+------+----------+
  # |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
  # +----+------+----------+------+----------+
  # | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
  # +----+------+----------+------+----------+
  defp handle_authentication(socket, transport) do
    case transport.recv(socket, 2, Config.read_timeout()) do
      {:ok, <<1, ulen>>} ->
        # Read username
        case transport.recv(socket, ulen, Config.read_timeout()) do
          {:ok, username_bin} ->
            # Read password length and password
            case transport.recv(socket, 1, Config.read_timeout()) do
              {:ok, <<plen>>} ->
                case transport.recv(socket, plen, Config.read_timeout()) do
                  {:ok, password_bin} ->
                    username = username_bin |> :binary.bin_to_list() |> to_string()
                    password = password_bin |> :binary.bin_to_list() |> to_string()

                    case Authentication.authenticate(username, password) do
                      :ok ->
                        Logger.info("SOCKS5 authentication successful for user: #{username}")
                        send_auth_success(socket, transport)
                        :ok

                      {:error, reason} ->
                        Logger.warning("SOCKS5 authentication failed for user: #{username}, reason: #{inspect(reason)}")
                        send_auth_failure(socket, transport)
                        {:error, :auth_failed}
                    end

                  {:error, reason} ->
                    {:error, reason}
                end

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
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
    # +----+--------+
    # |VER | STATUS |
    # +----+--------+
    # | 1  |   1    |
    # +----+--------+
    # STATUS: 0 = success
    response = <<1, 0>>
    transport.send(socket, response)
  end

  defp send_auth_failure(socket, transport) do
    # STATUS: non-zero = failure
    response = <<1, 1>>
    transport.send(socket, response)
  end

  # Step 4: Read connection request
  # +----+-----+-------+------+----------+----------+
  # |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
  # +----+-----+-------+------+----------+----------+
  # | 1  |  1  | X'00' |  1   | Variable |    2     |
  # +----+-----+-------+------+----------+----------+
  defp read_connect_request(socket, transport) do
    case transport.recv(socket, 4, Config.read_timeout()) do
      {:ok, <<@socks_version, @cmd_connect, 0, atyp>>} ->
        read_destination_address(socket, transport, atyp)

      {:ok, <<@socks_version, cmd, 0, _atyp>>} ->
        Logger.warning("Unsupported SOCKS5 command: #{cmd}")
        send_reply(socket, transport, @reply_command_not_supported, "0.0.0.0", 0)
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
            host = domain_bin |> :binary.bin_to_list() |> to_string()
            Logger.info("SOCKS5 CONNECT to #{host}:#{port} (domain)")
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
    send_reply(socket, transport, @reply_address_type_not_supported, "0.0.0.0", 0)
    {:error, :unsupported_address_type}
  end

  # Step 5: Establish tunnel
  defp establish_tunnel(socket, transport, target_host, target_port) do
    # Resolve DNS once and validate the resulting IP — closes DNS rebinding window
    case DestinationValidator.resolve_and_validate(target_host, target_port) do
      {:ok, ip_tuple} ->
        case TcpTunnel.connect_and_forward(socket, ip_tuple, target_port) do
          {:ok, target_socket} ->
            send_reply(socket, transport, @reply_success, target_host, target_port)
            {:ok, target_socket}

          {:error, reason} ->
            reply_code = ErrorHandler.socks5_reply_code(reason)
            send_reply(socket, transport, reply_code, target_host, target_port)
            {:error, reason}
        end

      {:error, reason} ->
        :telemetry.execute(
          [:edge_agent, :proxy, :socks5, :blocked],
          %{count: 1},
          %{reason: reason, host: target_host, port: target_port}
        )

        # Send SOCKS5 forbidden reply (connection not allowed by ruleset)
        send_reply(socket, transport, 2, target_host, target_port)
        {:error, reason}
    end
  end

  # Send SOCKS5 reply
  # +----+-----+-------+------+----------+----------+
  # |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
  # +----+-----+-------+------+----------+----------+
  # | 1  |  1  | X'00' |  1   | Variable |    2     |
  # +----+-----+-------+------+----------+----------+
  defp send_reply(socket, transport, reply_code, _host, _port) do
    # For simplicity, always return IPv4 0.0.0.0:0 as bind address
    response = <<@socks_version, reply_code, 0, @atyp_ipv4, 0, 0, 0, 0, 0::16>>
    transport.send(socket, response)
  end
end
