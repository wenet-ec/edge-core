# edge_agent/lib/edge_agent/metrics_server/config.ex
defmodule EdgeAgent.MetricsServer.Config do
  @moduledoc """
  Configuration management for the metrics server.

  Centralizes all hardcoded configuration values and provides
  a clean interface for accessing them.
  """

  @listen_address "0.0.0.0"
  @node_exporter_binary "/usr/local/bin/node_exporter"
  @host_proc_path "/host/proc"
  @host_sys_path "/host/sys"
  @host_root_path "/host"

  def host_metrics_port, do: Application.get_env(:edge_agent, :host_metrics_port)
  def listen_address, do: @listen_address
  def node_exporter_binary, do: @node_exporter_binary
  def host_proc_path, do: @host_proc_path
  def host_sys_path, do: @host_sys_path
  def host_root_path, do: @host_root_path

  def build_config do
    port = host_metrics_port()

    %{
      port: port,
      listen_address: @listen_address,
      binary_path: @node_exporter_binary,
      host_proc_path: @host_proc_path,
      host_sys_path: @host_sys_path,
      host_root_path: @host_root_path
    }
  end

  def node_exporter_args do
    port = host_metrics_port()

    [
      "--web.listen-address=#{@listen_address}:#{port}",
      "--path.procfs=#{@host_proc_path}",
      "--path.sysfs=#{@host_sys_path}",
      "--path.rootfs=#{@host_root_path}",
      "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
      "--collector.netdev.device-exclude=^(veth.*|docker.*|br-.*|lo)$$",
      "--no-collector.ipvs"
    ]
  end
end
