# edge_admin/lib/edge_admin/proxy_server/tcp_tunnel.ex
defmodule EdgeAdmin.ProxyServer.TcpTunnel do
  @moduledoc """
  Bidirectional TCP tunnel for admin proxy forwarding.

  Routes requests to Gateway based on cluster name extracted from target hostname.
  Supports two modes:
  1. Direct VPN: Routes directly to VPN nodes
  2. Proxy chaining: Routes through agent's proxy server as exit node
  """

  alias EdgeAdmin.EdgeClusters.Gateway

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

  # Direct VPN routing
  defp connect_direct(client_socket, target_host, target_port, caller_pid, initial_data) do
    case parse_cluster_from_hostname(target_host) do
      {:ok, cluster_name} ->
        connect_via_gateway(client_socket, cluster_name, target_host, target_port, caller_pid, initial_data)

      {:error, :not_vpn_target} ->
        Logger.error("Invalid target hostname: #{target_host}")
        {:error, :invalid_target}
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
    admin_name = find_cluster_owner(cluster_name)

    if admin_name do
      case :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_name}) do
        :undefined ->
          Logger.error("No Gateway found for cluster #{cluster_name}")
          {:error, :no_gateway}

        {gateway_pid, _meta} ->
          establish_connection_via_gateway(
            client_socket,
            gateway_pid,
            target_host,
            target_port,
            caller_pid,
            initial_data
          )
      end
    else
      Logger.error("No admin owns cluster #{cluster_name}")
      {:error, :no_cluster_owner}
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

      {:error, reason} ->
        Logger.error("Gateway failed to connect to #{target_host}:#{target_port}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Proxy chaining: Connect to agent's proxy server
  defp connect_via_agent_proxy(client_socket, exit_node, target_host, target_port, caller_pid, initial_data, protocol) do
    node_dns = EdgeAdmin.Nodes.Schemas.Node.dns_hostname(exit_node)
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

  defp get_agent_proxy_port(:http), do: Application.get_env(:edge_agent, :http_proxy_port, 43128)
  defp get_agent_proxy_port(:socks5), do: Application.get_env(:edge_agent, :socks5_proxy_port, 41080)

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
    admin_name = find_cluster_owner(cluster_name)

    if admin_name do
      case :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_name}) do
        :undefined ->
          Logger.error("No Gateway found for exit node cluster #{cluster_name}")
          {:error, :no_gateway}

        {gateway_pid, _meta} ->
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
      end
    else
      Logger.error("No admin owns cluster #{cluster_name}")
      {:error, :no_cluster_owner}
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
              Logger.error("Agent proxy rejected CONNECT: #{inspect(response)}")
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
         :ok <- send_socks5_auth(socket, proxy_password),
         :ok <- send_socks5_connect(socket, target_host, target_port, initial_data) do
      :ok
    end
  end

  defp send_socks5_greeting(socket) do
    greeting = <<5, 1, 2>>  # Version 5, 1 method, method 2 (username/password)

    case :gen_tcp.send(socket, greeting) do
      :ok ->
        case :gen_tcp.recv(socket, 2, 5000) do
          {:ok, <<5, 2>>} -> :ok
          {:ok, <<5, 0>>} -> :ok  # No auth required
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_socks5_auth(socket, proxy_password) do
    username = "_"
    auth_request =
      <<1, byte_size(username)::8>> <> username <>
        <<byte_size(proxy_password)::8>> <> proxy_password

    case :gen_tcp.send(socket, auth_request) do
      :ok ->
        case :gen_tcp.recv(socket, 2, 5000) do
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
        case :gen_tcp.recv(socket, 10, 5000) do
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
    case :gen_tcp.recv(socket, 0, 5000) do
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
            Logger.error("Agent proxy rejected CONNECT (remote): #{inspect(reason)}")
            {:error, :proxy_rejected}
        after
          10_000 ->
            {:error, :timeout}
        end

      :socks5 ->
        send(proxy_pid, {:consume_socks5_response, self()})

        receive do
          {:socks5_response_consumed, ^proxy_pid, {:ok, :accepted}} ->
            if initial_data, do: send(proxy_pid, {:send_to_target, initial_data})
            :ok

          {:socks5_response_consumed, ^proxy_pid, {:error, reason}} ->
            Logger.error("Agent proxy rejected SOCKS5 (remote): #{inspect(reason)}")
            {:error, :proxy_rejected}
        after
          10_000 ->
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

  # Find which admin owns this cluster from ETS metadata
  defp find_cluster_owner(cluster_name) do
    case :ets.lookup(:metadata, :edge_clusters) do
      [{:edge_clusters, assignments}] ->
        Enum.find_value(assignments, fn {admin_name, clusters} ->
          if Map.has_key?(clusters, cluster_name), do: admin_name
        end)

      [] ->
        nil
    end
  end

  # Forwarding loop: recv from source, send to destination
  defp forward_loop(source_socket, dest_socket) do
    case :gen_tcp.recv(source_socket, 0) do
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
