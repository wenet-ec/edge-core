# edge_agent/lib/edge_agent/ingress_tunneling/udp_transport.ex
defmodule EdgeAgent.IngressTunneling.UdpTransport do
  @moduledoc "Carries WireGuard datagrams between the isolated interface, DERP, and authenticated direct UDP paths."

  use GenServer

  alias EdgeAgent.IngressTunneling.Derp.Client
  alias EdgeAgent.IngressTunneling.Derp.Crypto
  alias EdgeAgent.IngressTunneling.Derp.DerpMap
  alias EdgeAgent.IngressTunneling.Stun

  require Logger

  @control_prefix "ECIT"
  @candidate_interval 5_000
  @path_check_interval 20_000
  @path_timeout 60_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec adapter_ports(pid()) :: {:ok, %{String.t() => :inet.port_number()}} | {:error, term()}
  def adapter_ports(pid), do: GenServer.call(pid, :adapter_ports)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, external_socket} <- open_socket({0, 0, 0, 0}),
         {:ok, peers, adapter_sockets, socket_peers, derp_clients} <- start_peers(opts) do
      {:ok,
       %{
         external_socket: external_socket,
         peers: peers,
         adapter_sockets: adapter_sockets,
         socket_peers: socket_peers,
         derp_clients: derp_clients,
         listen_port: Keyword.fetch!(opts, :listen_port),
         private_key: Keyword.fetch!(opts, :private_key),
         public_key: Keyword.fetch!(opts, :public_key),
         stun_servers: Keyword.fetch!(opts, :stun_servers),
         candidates: [],
         probes: %{}
       }, {:continue, :discover_candidates}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_continue(:discover_candidates, state), do: {:noreply, discover_candidates(state)}

  @impl GenServer
  def handle_info(:discover_candidates, state), do: {:noreply, discover_candidates(state)}

  @impl GenServer
  def handle_info({:candidate_discovery_result, {:ok, candidates}}, state) do
    Logger.info("Ingress direct-path candidates discovered: #{length(candidates)}")
    state = advertise_candidates(%{state | candidates: Enum.map(candidates, &parse_candidate!/1)})
    rearm(state.external_socket)
    schedule_candidates()
    schedule_path_check()
    {:noreply, state}
  end

  def handle_info({:candidate_discovery_result, {:error, reason}}, state) do
    Logger.warning("Ingress direct-path discovery failed: #{inspect(reason)}")
    rearm(state.external_socket)
    Process.send_after(self(), :discover_candidates, @candidate_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:advertise_candidates, state) do
    state = advertise_candidates(state)
    schedule_candidates()
    {:noreply, state}
  end

  def handle_info(:check_paths, state) do
    now = System.monotonic_time(:millisecond)

    peers =
      Map.new(state.peers, fn {key, peer} ->
        if peer.path != :derp and now - peer.last_direct_at > @path_timeout do
          Logger.info("Ingress direct path to #{short_key(key)} expired; using DERP")
          {key, %{peer | path: :derp}}
        else
          {key, peer}
        end
      end)

    state = probe_candidates(%{state | peers: peers})
    schedule_path_check()
    {:noreply, state}
  end

  def handle_info({:udp, socket, address, port, packet}, state) do
    rearm(socket)

    cond do
      socket == state.external_socket ->
        {:noreply, handle_external_packet(state, address, port, packet)}

      peer_key = Map.get(state.socket_peers, socket) ->
        {:noreply, send_wireguard_packet(state, peer_key, packet)}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:derp_packet, client, peer_key, packet}, state) do
    case peer_for_derp(state, client, peer_key) do
      nil ->
        {:noreply, state}

      {key, peer} ->
        case handle_peer_packet(state, key, peer, packet, :derp, nil) do
          {:ok, state} -> {:noreply, state}
          :ignore -> {:noreply, state}
        end
    end
  end

  def handle_info({:derp_peer_gone, _client, peer_key}, state) do
    Logger.debug("Ingress DERP reports peer gone: #{short_key(peer_key)}")
    {:noreply, state}
  end

  def handle_info({:derp_health, _client, _message}, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, reason}, state) do
    if pid in Map.values(state.derp_clients) do
      Logger.warning("Ingress DERP client exited: #{inspect(reason)}")
      {:stop, {:derp_client_exited, reason}, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:adapter_ports, _from, state) do
    ports = Map.new(state.peers, fn {key, peer} -> {key, peer.adapter_port} end)
    {:reply, {:ok, ports}, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.derp_clients, fn {_key, pid} -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    Enum.each(state.adapter_sockets, fn {_key, socket} -> close_socket(socket) end)
    close_socket(state.external_socket)
    :ok
  end

  defp start_peers(opts) do
    context = %{
      ingress_key: Keyword.fetch!(opts, :public_key),
      private_key: Keyword.fetch!(opts, :private_key),
      derp_map: Keyword.fetch!(opts, :derp_map)
    }

    opts
    |> Keyword.fetch!(:peers)
    |> Enum.reduce_while({:ok, %{}, %{}, %{}, %{}}, &start_peer(&1, &2, context))
    |> finish_peer_start()
  end

  defp start_peer(peer, {:ok, peers, adapters, reverse, clients}, context) do
    case start_peer_transport(peer, context) do
      {:ok, key, peer_state, adapter, client} ->
        {:cont,
         {:ok, Map.put(peers, key, peer_state), Map.put(adapters, key, adapter), Map.put(reverse, adapter, key),
          Map.put(clients, key, client)}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp start_peer_transport(peer, %{ingress_key: ingress_key, private_key: private_key, derp_map: derp_map}) do
    key = peer["tunnel_public_key"]
    {:ok, peer_key} = Base.decode64(key)
    relays = DerpMap.select_relays(derp_map, ingress_key, peer_key)

    with [_relay | _] <- relays,
         {:ok, adapter} <- open_socket({127, 0, 0, 1}),
         {:ok, {_loopback, adapter_port}} <- :inet.sockname(adapter),
         {:ok, client} <- start_derp_client(private_key, ingress_key, relays) do
      peer_state = %{config: peer, adapter_port: adapter_port, candidates: [], path: :derp, last_direct_at: 0}
      {:ok, key, peer_state, adapter, client}
    else
      [] -> {:error, {:no_derp_relay_for_peer, key}}
      {:error, reason} -> {:error, {:peer_transport_start_failed, key, reason}}
    end
  end

  defp start_derp_client(private_key, ingress_key, relays) do
    Client.start_link(
      private_key: private_key,
      public_key: ingress_key,
      relays: relays,
      owner: self()
    )
  end

  defp finish_peer_start({:ok, peers, adapters, reverse, clients}) do
    Enum.each(adapters, fn {_key, socket} -> rearm(socket) end)
    {:ok, peers, adapters, reverse, clients}
  end

  defp finish_peer_start(error), do: error

  defp send_wireguard_packet(state, peer_key, packet) do
    case Map.fetch(state.peers, peer_key) do
      {:ok, %{path: {:direct, address, port}}} ->
        case :gen_udp.send(state.external_socket, address, port, packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.debug("Ingress direct UDP send failed: #{inspect(reason)}")
            send_derp(state, peer_key, packet)
        end

      {:ok, _peer} ->
        send_derp(state, peer_key, packet)

      :error ->
        state
    end
  end

  defp send_derp(state, peer_key, packet) do
    case Map.fetch(state.derp_clients, peer_key) do
      {:ok, client} ->
        case Client.send_packet(client, peer_key, packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.debug("Ingress DERP packet send failed for #{short_key(peer_key)}: #{inspect(reason)}")
            state
        end

      :error ->
        state
    end
  catch
    :exit, _reason -> state
  end

  defp handle_external_packet(state, address, port, <<@control_prefix, encrypted::binary>>) do
    case decrypt_control(state, encrypted) do
      {:ok, key, message} -> handle_control(state, key, message, {address, port}, :direct)
      :error -> state
    end
  end

  defp handle_external_packet(state, address, port, packet) do
    case peer_for_candidate(state, address, port) do
      nil ->
        state

      key ->
        peer = Map.fetch!(state.peers, key)
        peers = Map.put(state.peers, key, %{peer | last_direct_at: System.monotonic_time(:millisecond)})
        inject_packet(%{state | peers: peers}, key, packet)
    end
  end

  defp handle_peer_packet(state, key, peer, <<@control_prefix, encrypted::binary>>, transport, endpoint) do
    case decrypt_control_from(key, state.private_key, encrypted) do
      {:ok, message} -> handle_control_message(state, key, peer, message, endpoint, transport)
      :error -> :ignore
    end
  end

  defp handle_peer_packet(state, key, _peer, packet, _transport, _endpoint),
    do: {:ok, inject_packet(state, key, packet)}

  defp decrypt_control(state, encrypted) do
    Enum.find_value(state.peers, :error, fn {key, _peer} ->
      case decrypt_control_from(key, state.private_key, encrypted) do
        {:ok, message} -> {:ok, key, message}
        :error -> nil
      end
    end)
  end

  defp decrypt_control_from(key, private_key, encrypted) do
    with {:ok, peer_key} <- Base.decode64(key),
         {:ok, message} <- Crypto.open(peer_key, private_key, encrypted),
         {:ok, %{"sender" => ^key} = data} <- JSON.decode(message) do
      {:ok, data}
    else
      _ -> :error
    end
  end

  defp handle_control(state, key, message, endpoint, transport) do
    case Map.fetch(state.peers, key) do
      {:ok, peer} ->
        case handle_control_message(state, key, peer, message, endpoint, transport) do
          {:ok, state} -> state
          :ignore -> state
        end

      :error ->
        state
    end
  end

  defp handle_control_message(
         state,
         key,
         peer,
         %{"kind" => "candidates", "candidates" => candidates},
         _endpoint,
         _transport
       )
       when is_list(candidates) do
    endpoints = Enum.flat_map(candidates, &parse_candidate/1)
    peers = Map.put(state.peers, key, %{peer | candidates: Enum.uniq(endpoints)})
    {:ok, probe_candidates(%{state | peers: peers}, [key])}
  end

  defp handle_control_message(state, key, _peer, %{"kind" => "probe", "nonce" => nonce}, endpoint, _transport)
       when is_binary(nonce) and not is_nil(endpoint) do
    {:ok, send_control_to_endpoint(state, key, "probe_ack", nonce, endpoint)}
  end

  defp handle_control_message(state, key, _peer, %{"kind" => "probe_ack", "nonce" => nonce}, endpoint, _transport)
       when is_binary(nonce) and not is_nil(endpoint) do
    if Map.get(state.probes, key) == nonce do
      {:ok, mark_direct(%{state | probes: Map.delete(state.probes, key)}, key, endpoint)}
    else
      :ignore
    end
  end

  defp handle_control_message(_state, _key, _peer, _message, _endpoint, _transport), do: :ignore

  defp advertise_candidates(%{candidates: []} = state), do: state

  defp advertise_candidates(state) do
    Enum.each(state.peers, fn {key, _peer} ->
      send_control(state, key, "candidates", Enum.map(state.candidates, &candidate_text/1))
    end)

    state
  end

  defp discover_candidates(state) do
    :ok = :inet.setopts(state.external_socket, active: false)

    owner = self()
    socket = state.external_socket
    stun_servers = state.stun_servers

    {:ok, _pid} =
      Task.start(fn ->
        result =
          try do
            {:ok, Enum.uniq(local_candidates(socket_port(socket)) ++ Stun.discover(socket, stun_servers))}
          rescue
            _error -> {:error, :candidate_discovery_failed}
          end

        send(owner, {:candidate_discovery_result, result})
      end)

    state
  end

  defp probe_candidates(state), do: probe_candidates(state, Map.keys(state.peers))

  defp probe_candidates(state, peer_keys) do
    Enum.reduce(peer_keys, state, fn key, current ->
      case Map.fetch(current.peers, key) do
        {:ok, %{candidates: endpoints}} when endpoints != [] ->
          nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
          probes = Map.put(current.probes, key, nonce)

          Enum.reduce(endpoints, %{current | probes: probes}, fn endpoint, state ->
            send_control_to_endpoint(state, key, "probe", nonce, endpoint)
          end)

        _ ->
          current
      end
    end)
  end

  defp send_control(state, key, kind, value) when kind == "candidates" do
    body = %{"kind" => kind, "sender" => Base.encode64(state.public_key), "candidates" => value}
    send_derp_control(state, key, body)
  end

  defp send_control_to_endpoint(state, key, kind, nonce, {address, port}) do
    body = %{"kind" => kind, "sender" => Base.encode64(state.public_key), "nonce" => nonce}

    case seal_control(state, key, body) do
      {:ok, packet} ->
        case :gen_udp.send(state.external_socket, address, port, packet) do
          :ok ->
            state

          {:error, reason} ->
            Logger.debug("Ingress UDP control send failed: #{inspect(reason)}")
            state
        end

      :error ->
        state
    end
  end

  defp send_derp_control(state, key, body) do
    with {:ok, packet} <- seal_control(state, key, body),
         {:ok, client} <- Map.fetch(state.derp_clients, key),
         :ok <- Client.send_packet(client, key, packet) do
      :ok
    else
      _ -> :error
    end

    state
  catch
    :exit, _reason -> state
  end

  defp seal_control(state, key, body) do
    with {:ok, peer_key} <- Base.decode64(key),
         {:ok, encrypted} <- Crypto.seal(peer_key, state.private_key, JSON.encode!(body)) do
      {:ok, @control_prefix <> encrypted}
    else
      _ -> :error
    end
  end

  defp inject_packet(state, key, packet) do
    case Map.fetch(state.adapter_sockets, key) do
      {:ok, socket} ->
        _ = :gen_udp.send(socket, {127, 0, 0, 1}, state.listen_port, packet)
        state

      :error ->
        state
    end
  end

  defp mark_direct(state, key, {address, port} = endpoint) do
    case Map.fetch(state.peers, key) do
      {:ok, peer} ->
        Logger.info("Ingress direct UDP path established for #{short_key(key)} at #{candidate_text(endpoint)}")

        %{
          state
          | peers:
              Map.put(state.peers, key, %{
                peer
                | path: {:direct, address, port},
                  last_direct_at: System.monotonic_time(:millisecond)
              })
        }

      :error ->
        state
    end
  end

  defp peer_for_candidate(state, address, port) do
    Enum.find_value(state.peers, fn {key, peer} ->
      if {address, port} in peer.candidates, do: key
    end)
  end

  defp peer_for_derp(state, client, peer_key) do
    case Enum.find(state.derp_clients, fn {_key, pid} -> pid == client end) do
      {key, _pid} when key == peer_key ->
        Map.get(state.peers, key) && {key, Map.fetch!(state.peers, key)}

      _ ->
        nil
    end
  end

  defp parse_candidate(candidate) when is_binary(candidate) do
    case String.split(candidate, ":", parts: 2) do
      [raw_address, raw_port] ->
        with {:ok, address} <- :inet.parse_ipv4_address(String.to_charlist(raw_address)),
             {port, ""} when port in 1..65_535 <- Integer.parse(raw_port) do
          [{address, port}]
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  defp parse_candidate(_candidate), do: []

  defp parse_candidate!({address, port}), do: {address, port}

  defp parse_candidate!(candidate) do
    case parse_candidate(candidate) do
      [endpoint] -> endpoint
      [] -> raise ArgumentError, "invalid discovered UDP candidate"
    end
  end

  defp local_candidates(port) do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        interfaces
        |> Enum.flat_map(fn {name, options} ->
          interface = to_string(name)

          if interface in ["lo", "netmaker", "edge_ingress"] do
            []
          else
            options
            |> Keyword.get_values(:addr)
            |> Enum.filter(&is_ipv4/1)
            |> Enum.reject(&private_loopback?/1)
            |> Enum.map(&{&1, port})
          end
        end)
        |> Enum.uniq()
        |> Enum.map(&candidate_text/1)

      {:error, _reason} ->
        []
    end
  end

  defp is_ipv4({_, _, _, _}), do: true
  defp is_ipv4(_address), do: false

  defp private_loopback?({127, _, _, _}), do: true
  defp private_loopback?(_address), do: false

  defp candidate_text({address, port}), do: "#{:inet.ntoa(address)}:#{port}"

  defp open_socket(address) do
    case :gen_udp.open(0, [:binary, active: false, ip: address, reuseaddr: true]) do
      {:ok, socket} -> socket |> :inet.setopts(active: :once) |> socket_open_result(socket)
      {:error, reason} -> {:error, reason}
    end
  end

  defp socket_open_result(:ok, socket), do: {:ok, socket}

  defp socket_open_result({:error, reason}, socket) do
    :gen_udp.close(socket)
    {:error, reason}
  end

  defp rearm(socket), do: :inet.setopts(socket, active: :once)

  defp socket_port(socket) do
    {:ok, {_address, port}} = :inet.sockname(socket)
    port
  end

  defp close_socket(socket) do
    :gen_udp.close(socket)
  rescue
    ArgumentError -> :ok
  end

  defp schedule_candidates, do: Process.send_after(self(), :advertise_candidates, @candidate_interval)
  defp schedule_path_check, do: Process.send_after(self(), :check_paths, @path_check_interval)
  defp short_key(key), do: String.slice(key, 0, 8)
end
