# edge_agent/lib/edge_agent/ingress_tunneling/system_command.ex
defmodule EdgeAgent.IngressTunneling.SystemCommand do
  @moduledoc "Runs the small set of operating-system commands required by Edge Ingress."

  @spec run(:ip | :iptables | :ip6tables | :wg | :dnsmasq, [String.t()]) ::
          {:ok, binary()} | {:error, term()}
  def run(:ip, args), do: run_command(fn -> System.cmd("ip", args, stderr_to_stdout: true) end)
  def run(:iptables, args), do: run_command(fn -> System.cmd("iptables", args, stderr_to_stdout: true) end)
  def run(:ip6tables, args), do: run_command(fn -> System.cmd("ip6tables", args, stderr_to_stdout: true) end)
  def run(:wg, args), do: run_command(fn -> System.cmd("wg", args, stderr_to_stdout: true) end)
  def run(:dnsmasq, args), do: run_command(fn -> System.cmd("dnsmasq", args, stderr_to_stdout: true) end)
  def run(_executable, _args), do: {:error, :unsupported_system_command}

  defp run_command(command) do
    case command.() do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {status, String.trim(output)}}
    end
  rescue
    error -> {:error, error}
  end
end
