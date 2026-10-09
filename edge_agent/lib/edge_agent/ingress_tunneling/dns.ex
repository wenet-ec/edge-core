# edge_agent/lib/edge_agent/ingress_tunneling/dns.ex
defmodule EdgeAgent.IngressTunneling.Dns do
  @moduledoc "Publishes only the selected Edge VPN DNS suffix on the Ingress addresses."

  alias EdgeAgent.IngressTunneling.SystemCommand

  @vpn_interface "netmaker"
  @config_path "/run/edge-agent/ingress-dnsmasq.conf"

  @doc "Starts a suffix-only DNS listener that forwards through the Agent's Edge VPN DNS listener."
  @spec start(map()) :: {:ok, port()} | {:error, term()}
  def start(config) do
    with {:ok, executable} <- executable("dnsmasq"),
         {:ok, upstream} <- vpn_dns_address(),
         :ok <- write_config(config, upstream),
         :ok <- validate_config() do
      start_dnsmasq(executable)
    end
  end

  @spec stop(port() | nil) :: :ok
  def stop(process) when is_port(process) do
    if Port.info(process), do: Port.close(process)
    File.rm(@config_path)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def stop(_process) do
    File.rm(@config_path)
    :ok
  end

  defp write_config(config, upstream) do
    addresses =
      (config["ingress_ipv4_addresses"] ++ config["ingress_ipv6_addresses"])
      |> Enum.map(&String.split(&1, "/", parts: 2))
      |> Enum.map(&hd/1)

    contents =
      [
        "no-resolv",
        "no-hosts",
        "bind-interfaces",
        "domain-needed",
        "listen-address=#{Enum.join(addresses, ",")}",
        "server=/#{config["vpn_dns_suffix"]}/#{upstream}"
      ]
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    with :ok <- File.mkdir_p(Path.dirname(@config_path)),
         :ok <- File.chmod(Path.dirname(@config_path), 0o700),
         :ok <- File.write(@config_path, contents, [:binary]) do
      File.chmod(@config_path, 0o600)
    end
  end

  defp validate_config do
    case SystemCommand.run(:dnsmasq, ["--test", "--conf-file=#{@config_path}"]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, {:dns_configuration_invalid, reason}}
    end
  end

  defp start_dnsmasq(executable) do
    {:ok,
     Port.open({:spawn_executable, executable}, [
       :binary,
       :exit_status,
       :use_stdio,
       :stderr_to_stdout,
       {:args, ["--keep-in-foreground", "--conf-file=#{@config_path}"]}
     ])}
  rescue
    error -> {:error, {:dns_start_failed, error}}
  end

  defp vpn_dns_address do
    with {:ok, output} <- SystemCommand.run(:ip, ["-4", "-o", "address", "show", "dev", @vpn_interface]),
         [_, address | _] <- Regex.run(~r/\binet\s+([0-9.]+)\//, output) do
      {:ok, address}
    else
      _ -> {:error, :edge_vpn_dns_listener_unavailable}
    end
  end

  defp executable(name) do
    case System.find_executable(name) do
      nil -> {:error, {:missing_executable, name}}
      path -> {:ok, path}
    end
  end
end
