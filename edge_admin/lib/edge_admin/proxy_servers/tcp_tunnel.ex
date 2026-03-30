# edge_admin/lib/edge_admin/proxy_servers/tcp_tunnel.ex
defmodule EdgeAdmin.ProxyServers.TcpTunnel do
  @moduledoc """
  Bidirectional TCP tunnel for admin proxy forwarding.

  Routes requests to Gateway based on cluster name extracted from target hostname.
  Supports two modes:
  1. Direct VPN: Routes directly to VPN nodes
  2. Proxy chaining: Routes through agent's proxy server as exit node
  """

  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler

  require Logger

  @doc """
  Connect to target host and start bidirectional forwarding.

  Options:
  - exit_node: Node struct for proxy chaining
  - protocol: :http or :socks5 (for proxy chaining)

  Returns:
  - {:ok, :local, target_socket} - Socket-based forwarding
  - {:ok, :remote, proxy_pid} - Message-based forwarding
  - {:error, reason} - Connection failed
  """
  def connect_and_forward(client_socket, target_host, target_port, caller_pid, initial_data \\ nil, opts \\ []) do
    case Keyword.get(opts, :exit_node) do
      nil ->
        connect_direct(client_socket, target_host, target_port, caller_pid, initial_data)

      exit_node ->
        protocol = Keyword.get(opts, :protocol, :http)
        connect_via_agent_proxy(client_socket, exit_node, target_host, target_port, caller_pid, initial_data, protocol)
    end
  end

  @doc """
  Returns the cluster name parsed from a VPN hostname, or nil if not a VPN target.

  Used by handlers to attach cluster attribution to telemetry after a successful tunnel.
  """
  def cluster_name_from_hostname(target_host) do
    case parse_cluster_from_hostname(target_host) do
      {:ok, cluster_name} -> cluster_name
      {:error, _} -> nil
    end
  end

  # Direct VPN routing
  defp connect_direct(client_socket, target_host, target_port, caller_pid, initial_data) do
    case parse_cluster_from_hostname(target_host) do
      {:ok, cluster_name} ->
        connect_via_gateway(client_socket, cluster_name, target_host, target_port, caller_pid, initial_data)

      {:error, :not_vpn_target} = error ->
        ErrorHandler.log_error(:invalid_target, %{target_host: target_host})
        error
    end
  end

  # Parse cluster name from VPN hostname (e.g., "node-*.cluster-default.nm.internal" -> "cluster-default")
  defp parse_cluster_from_hostname(target_host) do
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    pattern = ~r/(cluster-[^.]+)\.#{Regex.escape(domain)}$/

    case Regex.run(pattern, target_host) do
      [_, cluster_name] -> {:ok, cluster_name}
      nil -> {:error, :not_vpn_target}
    end
  end

  # Connect through Gateway to target
  defp connect_via_gateway(client_socket, cluster_name, target_host, target_port, caller_pid, initial_data) do
    case Gateway.lookup(cluster_name) do
      {:ok, gateway_pid} ->
        establish_connection_via_gateway(
          client_socket,
          gateway_pid,
          target_host,
          target_port,
          caller_pid,
          initial_data
        )

      {:error, :no_owner} = error ->
        ErrorHandler.log_error(:no_cluster_owner, %{cluster_name: cluster_name})
        error

      {:error, :gateway_not_found} = error ->
        ErrorHandler.log_error(:no_gateway, %{cluster_name: cluster_name})
        error
    end
  end

  defp establish_connection_via_gateway(client_socket, gateway_pid, target_host, target_port, caller_pid, initial_data) do
    case Gateway.tcp_connect(gateway_pid, target_host, target_port, caller_pid) do
      {:ok, target_socket} ->
        # Local connection: socket-based forwarding
        if initial_data, do: :gen_tcp.send(target_socket, initial_data)
        setup_bidirectional_forwarding(client_socket, target_socket)
        {:ok, :local, target_socket}

      {:ok, :remote, proxy_pid} ->
        # Remote connection: message-based streaming
        if initial_data, do: send(proxy_pid, {:send_to_target, initial_data})
        {:ok, :remote, proxy_pid}

      {:error, reason} = error ->
        ErrorHandler.log_error(reason, %{
          target_host: target_host,
          target_port: target_port,
          source: :gateway
        })

        error
    end
  end

  # Proxy chaining: Connect to agent's proxy server
  defp connect_via_agent_proxy(client_socket, exit_node, target_host, target_port, caller_pid, initial_data, protocol) do
    node_dns = EdgeAdmin.Nodes.Schemas.Node.vpn_hostname(exit_node)
    agent_proxy_port = get_agent_proxy_port(protocol)

    case parse_cluster_from_hostname(node_dns) do
      {:ok, cluster_name} ->
        route_through_agent_proxy(
          client_socket,
          cluster_name,
          node_dns,
          agent_proxy_port,
          target_host,
          target_port,
          caller_pid,
          initial_data,
          protocol,
          exit_node.proxy_password
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_agent_proxy_port(:http), do: Application.get_env(:edge_agent, :http_proxy_port, 43_128)
  defp get_agent_proxy_port(:socks5), do: Application.get_env(:edge_agent, :socks5_proxy_port, 41_080)

  defp route_through_agent_proxy(
         client_socket,
         cluster_name,
         node_dns,
         agent_proxy_port,
         target_host,
         target_port,
         caller_pid,
         initial_data,
         protocol,
         proxy_password
       ) do
    case Gateway.lookup(cluster_name) do
      {:ok, gateway_pid} ->
        connect_to_agent_proxy(
          client_socket,
          gateway_pid,
          node_dns,
          agent_proxy_port,
          target_host,
          target_port,
          caller_pid,
          initial_data,
          protocol,
          proxy_password
        )

      {:error, :no_owner} = error ->
        ErrorHandler.log_error(:no_cluster_owner, %{
          cluster_name: cluster_name,
          context: :proxy_chaining
        })

        error

      {:error, :gateway_not_found} = error ->
        ErrorHandler.log_error(:no_gateway, %{
          cluster_name: cluster_name,
          context: :proxy_chaining
        })

        error
    end
  end

  defp connect_to_agent_proxy(
         client_socket,
         gateway_pid,
         node_dns,
         agent_proxy_port,
         target_host,
         target_port,
         caller_pid,
         initial_data,
         protocol,
         proxy_password
       ) do
    case Gateway.tcp_connect(gateway_pid, node_dns, agent_proxy_port, caller_pid) do
      {:ok, agent_socket} ->
        case send_proxy_handshake(agent_socket, protocol, target_host, target_port, proxy_password, initial_data) do
          :ok ->
            setup_bidirectional_forwarding(client_socket, agent_socket)
            {:ok, :local, agent_socket}

          {:error, reason} ->
            :gen_tcp.close(agent_socket)
            {:error, reason}
        end

      {:ok, :remote, proxy_pid} ->
        send_proxy_handshake_remote(proxy_pid, protocol, target_host, target_port, proxy_password, initial_data)
        {:ok, :remote, proxy_pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Setup bidirectional forwarding between two sockets
  defp setup_bidirectional_forwarding(client_socket, target_socket) do
    forwarder_pid = spawn_link(fn -> forward_loop(client_socket, target_socket) end)
    :gen_tcp.controlling_process(client_socket, forwarder_pid)
    spawn_link(fn -> forward_loop(target_socket, client_socket) end)
  end

  # HTTP CONNECT handshake with agent proxy
  defp send_proxy_handshake(socket, :http, target_host, target_port, proxy_password, initial_data) do
    auth_header = "Proxy-Authorization: Basic #{Base.encode64("_:#{proxy_password}")}\r\n"

    request =
      "CONNECT #{target_host}:#{target_port} HTTP/1.1\r\n" <>
        "Host: #{target_host}:#{target_port}\r\n" <>
        auth_header <>
        "\r\n"

    case :gen_tcp.send(socket, request) do
      :ok ->
        case read_http_response(socket) do
          {:ok, response} ->
            if String.contains?(response, "200") do
              if initial_data, do: :gen_tcp.send(socket, initial_data)
              :ok
            else
              ErrorHandler.log_error(:proxy_rejected, %{
                response: response,
                protocol: :http
              })

              {:error, :proxy_rejected}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # SOCKS5 handshake with agent proxy
  defp send_proxy_handshake(socket, :socks5, target_host, target_port, proxy_password, initial_data) do
    with :ok <- send_socks5_greeting(socket),
         :ok <- send_socks5_auth(socket, proxy_password) do
      send_socks5_connect(socket, target_host, target_port, initial_data)
    end
  end

  defp send_socks5_greeting(socket) do
    # Version 5, 1 method, method 2 (username/password)
    greeting = <<5, 1, 2>>

    case :gen_tcp.send(socket, greeting) do
      :ok ->
        case :gen_tcp.recv(socket, 2, Config.handshake_timeout()) do
          {:ok, <<5, 2>>} -> :ok
          # No auth required
          {:ok, <<5, 0>>} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_socks5_auth(socket, proxy_password) do
    username = "_"

    auth_request =
      <<1, byte_size(username)::8>> <>
        username <>
        <<byte_size(proxy_password)::8>> <> proxy_password

    case :gen_tcp.send(socket, auth_request) do
      :ok ->
        case :gen_tcp.recv(socket, 2, Config.handshake_timeout()) do
          {:ok, <<1, 0>>} -> :ok
          {:ok, <<1, _status>>} -> {:error, :socks5_auth_failed}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_socks5_connect(socket, target_host, target_port, initial_data) do
    request = <<5, 1, 0, 3, byte_size(target_host)::8>> <> target_host <> <<target_port::16>>

    case :gen_tcp.send(socket, request) do
      :ok ->
        case :gen_tcp.recv(socket, 10, Config.handshake_timeout()) do
          {:ok, <<5, 0, _::binary>>} ->
            if initial_data, do: :gen_tcp.send(socket, initial_data)
            :ok

          {:ok, <<5, _status, _::binary>>} ->
            {:error, :socks5_connect_failed}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Read HTTP response headers (until \r\n\r\n)
  defp read_http_response(socket, buffer \\ "") do
    case :gen_tcp.recv(socket, 0, Config.handshake_timeout()) do
      {:ok, data} ->
        new_buffer = buffer <> data

        if String.contains?(new_buffer, "\r\n\r\n") do
          {:ok, new_buffer}
        else
          read_http_response(socket, new_buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Send proxy handshake for remote connections (via RemoteTunnel proxy)
  defp send_proxy_handshake_remote(proxy_pid, protocol, target_host, target_port, proxy_password, initial_data) do
    handshake = build_proxy_handshake(protocol, target_host, target_port, proxy_password)
    send(proxy_pid, {:send_to_target, handshake})

    # Wait for proxy to consume the response based on protocol
    case protocol do
      :http ->
        send(proxy_pid, {:consume_http_response, self()})

        receive do
          {:http_response_consumed, ^proxy_pid, {:ok, :accepted}} ->
            if initial_data, do: send(proxy_pid, {:send_to_target, initial_data})
            :ok

          {:http_response_consumed, ^proxy_pid, {:error, reason}} ->
            ErrorHandler.log_error(:proxy_rejected, %{
              reason: reason,
              protocol: :http,
              mode: :remote
            })

            {:error, :proxy_rejected}
        after
          Config.handshake_timeout() ->
            {:error, :timeout}
        end

      :socks5 ->
        send(proxy_pid, {:consume_socks5_response, self()})

        receive do
          {:socks5_response_consumed, ^proxy_pid, {:ok, :accepted}} ->
            if initial_data, do: send(proxy_pid, {:send_to_target, initial_data})
            :ok

          {:socks5_response_consumed, ^proxy_pid, {:error, reason}} ->
            ErrorHandler.log_error(:proxy_rejected, %{
              reason: reason,
              protocol: :socks5,
              mode: :remote
            })

            {:error, :proxy_rejected}
        after
          Config.handshake_timeout() ->
            {:error, :timeout}
        end
    end
  end

  defp build_proxy_handshake(:http, target_host, target_port, proxy_password) do
    auth_header = "Proxy-Authorization: Basic #{Base.encode64("_:#{proxy_password}")}\r\n"

    "CONNECT #{target_host}:#{target_port} HTTP/1.1\r\n" <>
      "Host: #{target_host}:#{target_port}\r\n" <>
      auth_header <>
      "\r\n"
  end

  defp build_proxy_handshake(:socks5, target_host, target_port, proxy_password) do
    username = "_"
    greeting = <<5, 1, 2>>
    auth = <<1, byte_size(username)::8>> <> username <> <<byte_size(proxy_password)::8>> <> proxy_password
    connect = <<5, 1, 0, 3, byte_size(target_host)::8>> <> target_host <> <<target_port::16>>
    IO.iodata_to_binary([greeting, auth, connect])
  end

  # Forwarding loop: recv from source, send to destination.
  # recv_timeout closes half-open connections where the peer disappeared without
  # a proper TCP close (NAT timeout, process kill, network cut).
  defp forward_loop(source_socket, dest_socket) do
    case :gen_tcp.recv(source_socket, 0, Config.recv_timeout()) do
      {:ok, data} ->
        case :gen_tcp.send(dest_socket, data) do
          :ok -> forward_loop(source_socket, dest_socket)
          {:error, _reason} -> cleanup_sockets(source_socket, dest_socket)
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
