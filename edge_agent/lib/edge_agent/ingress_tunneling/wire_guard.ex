# edge_agent/lib/edge_agent/ingress_tunneling/wire_guard.ex
defmodule EdgeAgent.IngressTunneling.WireGuard do
  @moduledoc "Runs the isolated userspace WireGuard interface used by Edge Ingress."

  alias EdgeAgent.IngressTunneling.SystemCommand

  @interface "edge_ingress"
  @mtu 1_420

  @spec start(map(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def start(config, listen_port) when is_integer(listen_port) and listen_port in 1..65_535 do
    with {:ok, executable} <- executable("wireguard-go"),
         :ok <- tun_device_available() do
      with {:ok, process} <- start_engine(executable) do
        runtime = %{interface: @interface, process: process, listen_port: listen_port}

        result =
          with :ok <- wait_for_interface(),
               :ok <- configure_interface(config, listen_port),
               :ok <- set_addresses(config),
               :ok <- set_link_up() do
            {:ok, runtime}
          end

        case result do
          {:ok, _runtime} ->
            result

          {:error, _reason} = error ->
            stop(runtime)
            error
        end
      end
    end
  end

  @spec free_udp_port() :: {:ok, pos_integer()} | {:error, term()}
  def free_udp_port do
    case :gen_udp.open(0, [:binary, active: false]) do
      {:ok, socket} ->
        result =
          case :inet.sockname(socket) do
            {:ok, {_address, port}} -> {:ok, port}
            {:error, reason} -> {:error, reason}
          end

        :gen_udp.close(socket)
        result

      {:error, reason} ->
        {:error, {:wireguard_port_unavailable, reason}}
    end
  end

  @spec configure_peers(map(), map(), [map()]) :: :ok | {:error, term()}
  def configure_peers(runtime, adapter_ports, peers) do
    peer_configs =
      Enum.map(peers, fn peer ->
        key = Map.fetch!(peer, "tunnel_public_key")
        endpoint_port = Map.fetch!(adapter_ports, key)

        Enum.join(
          [
            "[Peer]",
            "PublicKey = #{key}",
            "AllowedIPs = #{Enum.join(Map.fetch!(peer, "allowed_ips"), ", ")}",
            "Endpoint = 127.0.0.1:#{endpoint_port}",
            "PersistentKeepalive = 25"
          ],
          "\n"
        )
      end)

    config = Enum.join(peer_configs, "\n") <> "\n"

    with :ok <- sync_configuration(runtime.interface, config) do
      install_peer_routes(runtime.interface, peers)
    end
  end

  @spec stop(map() | nil) :: :ok
  def stop(nil) do
    _ = SystemCommand.run(:ip, ["link", "delete", "dev", @interface])
    :ok
  end

  def stop(%{interface: interface} = runtime) do
    case Map.get(runtime, :process) do
      port when is_port(port) ->
        if Port.info(port), do: Port.close(port)

      _ ->
        :ok
    end

    _ = SystemCommand.run(:ip, ["link", "delete", "dev", interface])

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp start_engine(executable) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, ["-f", @interface]}
      ])

    {:ok, port}
  rescue
    error -> {:error, {:wireguard_engine_start_failed, error}}
  end

  defp wait_for_interface(attempt \\ 0)
  defp wait_for_interface(attempt) when attempt >= 50, do: {:error, :wireguard_interface_timeout}

  defp wait_for_interface(attempt) do
    case SystemCommand.run(:ip, ["link", "show", "dev", @interface]) do
      {:ok, _output} ->
        :ok

      {:error, _reason} ->
        Process.sleep(100)
        wait_for_interface(attempt + 1)
    end
  end

  defp configure_interface(config, port) do
    contents = "[Interface]\nPrivateKey = #{Map.fetch!(config, "private_key")}\nListenPort = #{port}\n"

    with {:ok, path} <- write_private_config(contents) do
      result = SystemCommand.run(:wg, ["setconf", @interface, path])
      File.rm(path)
      command_result(result)
    end
  end

  defp sync_configuration(interface, peers) do
    with {:ok, path} <- write_private_config("[Interface]\n" <> peers) do
      result = SystemCommand.run(:wg, ["syncconf", interface, path])
      File.rm(path)
      command_result(result)
    end
  end

  defp command_result({:ok, _output}), do: :ok
  defp command_result({:error, _reason} = error), do: error

  defp write_private_config(contents) do
    directory = "/run/edge-agent"
    path = Path.join(directory, "ingress-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}.conf")

    with :ok <- File.mkdir_p(directory),
         :ok <- File.chmod(directory, 0o700),
         :ok <- File.write(path, contents, [:binary]),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} ->
        _ = File.rm(path)
        {:error, {:private_configuration_write_failed, reason}}
    end
  end

  defp set_addresses(config) do
    with :ok <- address_commands(config["ingress_ipv4_addresses"], "-4") do
      address_commands(config["ingress_ipv6_addresses"], "-6")
    end
  end

  defp address_commands(addresses, family_flag) do
    Enum.reduce_while(addresses, :ok, fn address, :ok ->
      case SystemCommand.run(:ip, [family_flag, "address", "replace", address, "dev", @interface]) do
        {:ok, _output} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:interface_address_failed, address, reason}}}
      end
    end)
  end

  defp set_link_up do
    with {:ok, _} <- SystemCommand.run(:ip, ["link", "set", "dev", @interface, "mtu", Integer.to_string(@mtu)]),
         {:ok, _} <- SystemCommand.run(:ip, ["link", "set", "dev", @interface, "up"]) do
      :ok
    end
  end

  defp install_peer_routes(interface, peers) do
    peers
    |> Enum.flat_map(&Map.fetch!(&1, "allowed_ips"))
    |> Enum.reduce_while(:ok, fn cidr, :ok ->
      family_flag = if String.contains?(cidr, ":"), do: "-6", else: "-4"

      case SystemCommand.run(:ip, [family_flag, "route", "replace", cidr, "dev", interface]) do
        {:ok, _output} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:peer_route_failed, cidr, reason}}}
      end
    end)
  end

  defp tun_device_available do
    case File.stat("/dev/net/tun") do
      {:ok, %{type: :device}} -> :ok
      {:ok, _} -> {:error, :tun_device_unavailable}
      {:error, reason} -> {:error, {:tun_device_unavailable, reason}}
    end
  end

  defp executable(name) do
    case System.find_executable(name) do
      nil -> {:error, {:missing_executable, name}}
      path -> {:ok, path}
    end
  end
end
