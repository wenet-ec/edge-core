# edge_agent/lib/edge_agent_metrics/config.ex
defmodule EdgeAgentMetrics.Config do
  @moduledoc """
  Configuration management for the metrics exporter pair.

  Centralizes the static binary paths and host bind-mount paths (module
  attributes) alongside env-driven settings (`:host_metrics_port`,
  `:wireguard_metrics_port`) and exposes a single `build_config/0` snapshot
  used by the GenServer.
  """

  # node_exporter delegates listener creation to prometheus/exporter-toolkit;
  # wireguard_exporter delegates to Tokio. Both accept an IPv6 unspecified
  # address, which is dual-stack on our supported Linux hosts (bindv6only=0).
  @listen_address_ipv6 "::"
  @node_exporter_binary "/usr/local/bin/node_exporter"
  @wireguard_exporter_binary "/usr/local/bin/prometheus_wireguard_exporter"
  @host_proc_path "/host/proc"
  @host_sys_path "/host/sys"
  @host_root_path "/host"

  def host_metrics_port, do: Application.get_env(:edge_agent, :host_metrics_port)
  def wireguard_metrics_port, do: Application.get_env(:edge_agent, :wireguard_metrics_port)
  def listen_address, do: @listen_address_ipv6
  def node_exporter_binary, do: @node_exporter_binary
  def wireguard_exporter_binary, do: @wireguard_exporter_binary
  def host_proc_path, do: @host_proc_path
  def host_sys_path, do: @host_sys_path
  def host_root_path, do: @host_root_path

  def build_config do
    %{
      host_metrics_port: host_metrics_port(),
      wireguard_metrics_port: wireguard_metrics_port(),
      listen_address: @listen_address_ipv6,
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
      "--web.listen-address=[#{@listen_address_ipv6}]:#{port}",
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

    # This exporter exposes one listener only. Its Tokio listener on "::" is
    # dual-stack on supported Linux hosts (net.ipv6.bindv6only=0), matching
    # node_exporter's IPv6 wildcard listener above.
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
