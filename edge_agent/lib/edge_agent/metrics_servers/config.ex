# edge_agent/lib/edge_agent/metrics_servers/config.ex
defmodule EdgeAgent.MetricsServers.Config do
  @moduledoc """
  Configuration management for the metrics exporter pair.

  Centralizes the static binary paths and host bind-mount paths (module
  attributes) alongside env-driven settings (`:host_metrics_port`,
  `:wireguard_metrics_port`) and exposes a single `build_config/0` snapshot
  used by the GenServer.
  """

  @listen_address "0.0.0.0"
  @listen_address_ipv6 "::"
  @node_exporter_binary "/usr/local/bin/node_exporter"
  @wireguard_exporter_binary "/usr/local/bin/prometheus_wireguard_exporter"
  @host_proc_path "/host/proc"
  @host_sys_path "/host/sys"
  @host_root_path "/host"

  def host_metrics_port, do: Application.get_env(:edge_agent, :host_metrics_port)
  def wireguard_metrics_port, do: Application.get_env(:edge_agent, :wireguard_metrics_port)
  def listen_address, do: @listen_address
  def node_exporter_binary, do: @node_exporter_binary
  def wireguard_exporter_binary, do: @wireguard_exporter_binary
  def host_proc_path, do: @host_proc_path
  def host_sys_path, do: @host_sys_path
  def host_root_path, do: @host_root_path

  def build_config do
    %{
      host_metrics_port: host_metrics_port(),
      wireguard_metrics_port: wireguard_metrics_port(),
      listen_address: @listen_address,
      node_exporter_binary: @node_exporter_binary,
      wireguard_exporter_binary: @wireguard_exporter_binary,
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
      "--no-collector.ipvs",
      "--collector.processes",
      "--collector.systemd",
      "--collector.tcpstat",
      "--collector.wifi"
    ]
  end

  def wireguard_exporter_args do
    port = wireguard_metrics_port()

    # wireguard_exporter binds to "::" (IPv6 unspecified) so a dual-stack
    # Linux host accepts both IPv4 and IPv6 scrapes through a single
    # listener. node_exporter binds to "0.0.0.0" (IPv4-only) for symmetry
    # with how Prometheus scrapes it from sibling containers.
    [
      "--port",
      "#{port}",
      "--address",
      "#{@listen_address_ipv6}",
      "--verbose",
      "true",
      "--separate_allowed_ips",
      "true",
      "--export_remote_ip_and_port",
      "true",
      "--export_latest_handshake_delay",
      "true"
    ]
  end
end
