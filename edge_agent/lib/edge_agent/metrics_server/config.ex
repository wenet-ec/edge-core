# edge_agent/lib/edge_agent/metrics_server/config.ex
defmodule EdgeAgent.MetricsServer.Config do
  @moduledoc """
  Configuration management for the metrics server.

  Centralizes all hardcoded configuration values and provides
  a clean interface for accessing them.
  """

  @metrics_port 9100
  @listen_address "0.0.0.0"
  @node_exporter_binary "/usr/local/bin/node_exporter"
  @host_proc_path "/host/proc"
  @host_sys_path "/host/sys"
  @host_root_path "/host"
  @tailscale_state_dir "/var/lib/tailscale"
  @tailscale_state_file "/var/lib/tailscale/tailscaled.state"
  @tailscale_socket "/var/run/tailscale/tailscaled.sock"
  @tailscale_cache_dir "/var/cache/tailscale"

  def metrics_port, do: @metrics_port
  def listen_address, do: @listen_address
  def node_exporter_binary, do: @node_exporter_binary
  def host_proc_path, do: @host_proc_path
  def host_sys_path, do: @host_sys_path
  def host_root_path, do: @host_root_path
  def tailscale_state_dir, do: @tailscale_state_dir
  def tailscale_state_file, do: @tailscale_state_file
  def tailscale_socket, do: @tailscale_socket
  def tailscale_cache_dir, do: @tailscale_cache_dir

  @doc """
  Returns the complete configuration as a map.
  """
  def build_config do
    %{
      port: @metrics_port,
      listen_address: @listen_address,
      binary_path: @node_exporter_binary,
      host_proc_path: @host_proc_path,
      host_sys_path: @host_sys_path,
      host_root_path: @host_root_path,
      tailscale_state_dir: @tailscale_state_dir,
      tailscale_state_file: @tailscale_state_file,
      tailscale_socket: @tailscale_socket,
      tailscale_cache_dir: @tailscale_cache_dir
    }
  end

  @doc """
  Returns the command line arguments for node_exporter.
  """
  def node_exporter_args do
    [
      "--web.listen-address=#{@listen_address}:#{@metrics_port}",
      "--path.procfs=#{@host_proc_path}",
      "--path.sysfs=#{@host_sys_path}",
      "--path.rootfs=#{@host_root_path}",
      "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
      "--collector.netdev.device-exclude=^(veth.*|docker.*|br-.*|lo)$$",
      "--no-collector.ipvs"
    ]
  end
end
