# edge_agent/lib/edge_agent/ingress_tunneling/runtime.ex
defmodule EdgeAgent.IngressTunneling.Runtime do
  @moduledoc "Applies one complete Ingress Tunneling snapshot to the local network namespace."

  alias EdgeAgent.IngressTunneling.Dns
  alias EdgeAgent.IngressTunneling.Forwarding
  alias EdgeAgent.IngressTunneling.UdpTransport
  alias EdgeAgent.IngressTunneling.WireGuard
  alias EdgeAgent.Settings

  require Logger

  @doc "Starts the isolated WireGuard, transport, DNS, and forwarding runtime for a snapshot."
  @spec start(map(), map()) :: {:ok, map()} | {:error, term()}
  def start(config, derp_map) do
    case private_key() do
      {:ok, private_key} -> start_with_key(config, derp_map, private_key)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop(map() | nil) :: :ok
  def stop(nil) do
    WireGuard.stop(%{interface: "edge_ingress"})
    Dns.stop(nil)
    Forwarding.remove()
    :ok
  end

  def stop(runtime) do
    Dns.stop(runtime[:dns])

    if is_pid(runtime[:transport]) and Process.alive?(runtime[:transport]) do
      GenServer.stop(runtime[:transport], :normal)
    end

    WireGuard.stop(runtime[:wireguard])
    Forwarding.remove()
    :ok
  catch
    :exit, _reason ->
      WireGuard.stop(runtime[:wireguard])
      Forwarding.remove()
      :ok
  end

  defp start_transport(config, derp_map, private_key, listen_port) do
    {:ok, public_key} = Base.decode64(config["ingress_public_key"])

    UdpTransport.start_link(
      peers: config["peers"],
      private_key: private_key,
      public_key: public_key,
      derp_map: derp_map,
      stun_servers: config["core_stun_servers"],
      listen_port: listen_port
    )
  end

  defp start_with_key(config, derp_map, private_key) do
    with {:ok, listen_port} <- WireGuard.free_udp_port(),
         :ok <- block_listener(listen_port),
         {:ok, wireguard} <- start_wireguard(config, private_key, listen_port),
         :ok <- install_forwarding(config, wireguard) do
      configure_runtime(config, derp_map, private_key, wireguard)
    else
      {:error, reason} ->
        Forwarding.remove()
        {:error, reason}
    end
  end

  defp block_listener(listen_port) do
    case Forwarding.block_listener(listen_port) do
      :ok ->
        :ok

      {:error, reason} ->
        Forwarding.remove()
        {:error, reason}
    end
  end

  defp start_wireguard(config, private_key, listen_port) do
    case WireGuard.start(Map.put(config, "private_key", Base.encode64(private_key)), listen_port) do
      {:ok, wireguard} ->
        {:ok, wireguard}

      {:error, reason} ->
        Forwarding.remove()
        {:error, reason}
    end
  end

  defp install_forwarding(config, wireguard) do
    case Forwarding.install(config) do
      :ok ->
        :ok

      {:error, reason} ->
        WireGuard.stop(wireguard)
        Forwarding.remove()
        {:error, reason}
    end
  end

  defp configure_runtime(config, derp_map, private_key, wireguard) do
    runtime = %{wireguard: wireguard, transport: nil, dns: nil}

    case start_transport(config, derp_map, private_key, wireguard.listen_port) do
      {:ok, transport} ->
        runtime = %{runtime | transport: transport}

        result =
          with {:ok, adapter_ports} <- UdpTransport.adapter_ports(transport),
               :ok <- WireGuard.configure_peers(wireguard, adapter_ports, config["peers"]),
               {:ok, dns} <- start_dns(config) do
            {:ok, %{runtime | dns: dns}}
          end

        case result do
          {:ok, complete_runtime} ->
            Logger.info(
              "Edge Ingress interface #{wireguard.interface} started for #{length(config["peers"])} Tunnel peer(s)"
            )

            {:ok, complete_runtime}

          {:error, reason} ->
            stop(runtime)
            Logger.error("Edge Ingress startup failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        stop(runtime)
        {:error, reason}
    end
  end

  defp start_dns(%{"peers" => []}), do: {:ok, nil}
  defp start_dns(config), do: Dns.start(config)

  defp private_key do
    case Settings.get_ingress_private_key() do
      nil ->
        {:error, :ingress_private_key_missing}

      encoded ->
        case Base.decode64(encoded) do
          {:ok, <<_::binary-size(32)>> = key} -> {:ok, key}
          _ -> {:error, :ingress_private_key_invalid}
        end
    end
  end
end
