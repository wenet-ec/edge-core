# edge_agent/lib/edge_agent/ingress_tunneling/derp/client.ex
defmodule EdgeAgent.IngressTunneling.Derp.Client do
  @moduledoc "Maintains an authenticated DERP connection and exchanges peer WireGuard packets."

  use GenServer

  alias EdgeAgent.IngressTunneling.Derp.Crypto
  alias EdgeAgent.IngressTunneling.Derp.Frame

  require Logger

  @frame_server_key 0x01
  @frame_client_info 0x02
  @frame_server_info 0x03
  @frame_send_packet 0x04
  @frame_recv_packet 0x05
  @frame_peer_gone 0x08
  @frame_ping 0x12
  @frame_pong 0x13
  @frame_health 0x14
  @protocol_version 2
  @max_buffer_size 1_048_581
  @connect_timeout 10_000
  @retry_interval 5_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec send_packet(pid(), binary(), binary()) :: :ok | {:error, term()}
  def send_packet(pid, peer_public_key, packet) do
    GenServer.call(pid, {:send_packet, peer_public_key, packet}, 5_000)
  end

  @impl GenServer
  def init(opts) do
    case {Keyword.get(opts, :private_key), Keyword.get(opts, :public_key), Keyword.get(opts, :relays),
          Keyword.get(opts, :owner)} do
      {private_key, public_key, [_relay | _] = relays, owner}
      when is_binary(private_key) and is_binary(public_key) and is_pid(owner) ->
        {:ok,
         %{
           private_key: private_key,
           public_key: public_key,
           relays: relays,
           relay_index: 0,
           relay: hd(relays),
           owner: owner,
           socket: nil,
           buffer: <<>>
         }, {:continue, :connect}}

      _invalid_opts ->
        {:stop, :invalid_derp_client_options}
    end
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, socket} ->
        Logger.info("Ingress DERP connection established at #{relay_label(state.relay)}")
        :ok = :ssl.setopts(socket, active: :once)
        {:noreply, %{state | socket: socket, buffer: <<>>}}

      {:error, reason} ->
        Logger.warning("Ingress DERP connection failed at #{relay_label(state.relay)}: #{inspect(reason)}")
        Process.send_after(self(), :reconnect, @retry_interval)
        {:noreply, next_relay(state)}
    end
  end

  @impl GenServer
  def handle_call({:send_packet, _peer_public_key, _packet}, _from, %{socket: nil} = state),
    do: {:reply, {:error, :unavailable}, state}

  def handle_call({:send_packet, peer_public_key, packet}, _from, state)
      when is_binary(peer_public_key) and is_binary(packet) do
    with {:ok, peer_public_key} <- decode_key(peer_public_key),
         {:ok, frame} <- Frame.encode(@frame_send_packet, peer_public_key <> packet),
         :ok <- :ssl.send(state.socket, frame) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:reconnect, %{socket: nil} = state), do: {:noreply, state, {:continue, :connect}}

  def handle_info({:ssl, socket, data}, %{socket: socket} = state) do
    case consume_frames(state.buffer <> data, state.owner) do
      {:ok, buffer} when byte_size(buffer) <= @max_buffer_size ->
        case :ssl.setopts(socket, active: :once) do
          :ok -> {:noreply, %{state | buffer: buffer}}
          {:error, reason} -> disconnect(state, {:setopts, reason})
        end

      {:ok, _buffer} ->
        disconnect(state, :frame_buffer_limit_exceeded)

      {:error, reason} ->
        disconnect(state, reason)
    end
  end

  def handle_info({:ssl_closed, socket}, %{socket: socket} = state), do: disconnect(state, :closed)
  def handle_info({:ssl_error, socket, reason}, %{socket: socket} = state), do: disconnect(state, reason)

  def handle_info({:send_frame, type, payload}, %{socket: socket} = state) when not is_nil(socket) do
    case Frame.encode(type, payload) do
      {:ok, frame} ->
        case :ssl.send(socket, frame) do
          :ok -> {:noreply, state}
          {:error, reason} -> disconnect(state, reason)
        end

      {:error, reason} ->
        disconnect(state, reason)
    end
  end

  def handle_info({:send_frame, _type, _payload}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def format_status(_reason, [_process_dictionary, state]) do
    [data: [{~c"State", Map.put(state, :private_key, :redacted)}]]
  end

  @impl GenServer
  def terminate(_reason, %{socket: nil}), do: :ok
  def terminate(_reason, %{socket: socket}), do: :ssl.close(socket)

  defp connect(state) do
    relay = state.relay

    case tls_connect(relay) do
      {:ok, socket} ->
        case handshake(socket, relay, state) do
          {:ok, _server_key} ->
            {:ok, socket}

          {:error, reason} ->
            :ssl.close(socket)
            Logger.debug("DERP handshake failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handshake(socket, relay, state) do
    with :ok <- request_upgrade(socket, relay),
         {:ok, server_key} <- receive_server_key(socket),
         :ok <- send_client_info(socket, server_key, state),
         :ok <- receive_server_info(socket, server_key, state.private_key) do
      {:ok, server_key}
    end
  end

  defp tls_connect(%{host: host, port: port, tls_server_name: server_name}) do
    host_charlist = String.to_charlist(host)
    server_name = if server_name in [nil, ""], do: host, else: server_name

    options = [
      :binary,
      active: false,
      packet: :raw,
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(server_name),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      alpn_advertised_protocols: ["http/1.1"]
    ]

    :ssl.connect(host_charlist, port, options, @connect_timeout)
  end

  defp request_upgrade(socket, %{host: host, port: port}) do
    host_header = if port == 443, do: host, else: "#{host}:#{port}"

    request =
      "GET /derp HTTP/1.1\r\n" <>
        "Host: #{host_header}\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Upgrade: DERP\r\n\r\n"

    with :ok <- :ssl.send(socket, request),
         {:ok, response} <- receive_http_headers(socket, <<>>, 0),
         [status | _headers] <- String.split(response, "\r\n"),
         true <- String.contains?(status, " 101 ") do
      :ok
    else
      false -> {:error, :derp_upgrade_rejected}
      [] -> {:error, :invalid_http_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp receive_http_headers(_socket, _response, size) when size > 16_384, do: {:error, :http_headers_too_large}

  defp receive_http_headers(socket, response, size) do
    case :ssl.recv(socket, 1, @connect_timeout) do
      {:ok, <<byte>>} ->
        response = response <> <<byte>>

        if String.ends_with?(response, "\r\n\r\n") do
          {:ok, response}
        else
          receive_http_headers(socket, response, size + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_server_key(socket) do
    with {:ok, type, payload} <- receive_frame(socket),
         true <- type == @frame_server_key,
         <<"DERP", 0xF0, 0x9F, 0x94, 0x91, server_key::binary-size(32), _::binary>> <- payload do
      {:ok, server_key}
    else
      false -> {:error, :invalid_server_key_frame}
      {:ok, _type, _payload} -> {:error, :invalid_server_key_frame}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_server_key_frame}
    end
  end

  defp send_client_info(socket, server_key, state) do
    info = JSON.encode!(%{"version" => @protocol_version, "CanAckPings" => true})

    with {:ok, boxed} <- Crypto.seal(server_key, state.private_key, info),
         {:ok, frame} <- Frame.encode(@frame_client_info, state.public_key <> boxed) do
      :ssl.send(socket, frame)
    end
  end

  defp receive_server_info(socket, server_key, private_key) do
    with {:ok, type, <<_nonce::binary-size(24), _ciphertext::binary>> = payload} <- receive_frame(socket),
         true <- type == @frame_server_info,
         {:ok, message} <- Crypto.open(server_key, private_key, payload),
         {:ok, %{"version" => @protocol_version}} <- JSON.decode(message) do
      :ok
    else
      false -> {:error, :invalid_server_info_frame}
      {:ok, _type, _payload} -> {:error, :invalid_server_info_frame}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_server_info}
    end
  end

  defp receive_frame(socket) do
    with {:ok, <<type, length::unsigned-big-32>>} <- :ssl.recv(socket, 5, @connect_timeout),
         true <- length <= @max_buffer_size,
         {:ok, payload} <- :ssl.recv(socket, length, @connect_timeout) do
      {:ok, type, payload}
    else
      false -> {:error, :frame_too_large}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_frame_header}
    end
  end

  defp consume_frames(buffer, owner) do
    case Frame.decode(buffer) do
      {:ok, frame} ->
        dispatch_frame(frame, owner)

      {:error, :incomplete} ->
        {:ok, buffer}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch_frame({@frame_recv_packet, <<source_key::binary-size(32), packet::binary>>, rest}, owner) do
    send(owner, {:derp_packet, self(), Base.encode64(source_key), packet})
    consume_frames(rest, owner)
  end

  defp dispatch_frame({@frame_ping, payload, rest}, owner) when byte_size(payload) == 8 do
    send(self(), {:send_frame, @frame_pong, payload})
    consume_frames(rest, owner)
  end

  defp dispatch_frame({@frame_peer_gone, <<peer_key::binary-size(32), _reason, _::binary>>, rest}, owner),
    do: report_peer_gone(peer_key, rest, owner)

  defp dispatch_frame({@frame_peer_gone, <<peer_key::binary-size(32)>>, rest}, owner),
    do: report_peer_gone(peer_key, rest, owner)

  defp dispatch_frame({@frame_health, message, rest}, owner) do
    send(owner, {:derp_health, self(), message})
    consume_frames(rest, owner)
  end

  defp dispatch_frame({_type, _payload, rest}, owner), do: consume_frames(rest, owner)

  defp report_peer_gone(peer_key, rest, owner) do
    send(owner, {:derp_peer_gone, self(), Base.encode64(peer_key)})
    consume_frames(rest, owner)
  end

  defp disconnect(%{socket: socket} = state, reason) do
    if socket, do: :ssl.close(socket)
    Logger.debug("Ingress DERP connection disconnected: #{inspect(reason)}")
    Process.send_after(self(), :reconnect, @retry_interval)
    {:noreply, %{next_relay(state) | socket: nil, buffer: <<>>}}
  end

  defp decode_key(key) do
    case Base.decode64(key) do
      {:ok, <<_::binary-size(32)>> = raw_key} -> {:ok, raw_key}
      _ -> {:error, :invalid_peer_key}
    end
  end

  defp relay_label(%{host: host, port: port}), do: "#{host}:#{port}"

  defp next_relay(%{relays: relays, relay_index: index} = state) do
    next_index = rem(index + 1, length(relays))
    %{state | relay_index: next_index, relay: Enum.at(relays, next_index)}
  end
end
