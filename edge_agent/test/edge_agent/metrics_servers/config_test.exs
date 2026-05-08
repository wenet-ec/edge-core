# edge_agent/test/edge_agent/metrics_servers/config_test.exs
defmodule EdgeAgent.MetricsServers.ConfigTest do
  # async: false — node_exporter_args/0 / wireguard_exporter_args/0 read
  # :host_metrics_port and :wireguard_metrics_port from app env. We snapshot
  # and restore around env-touching tests; serial execution avoids races.
  use ExUnit.Case, async: false

  alias EdgeAgent.MetricsServers.Config

  # ---------------------------------------------------------------------------
  # Constant getters — pinned values. These are operationally meaningful: the
  # binary paths must match what the container image installs; the listen
  # address must match what Prometheus scrapes.
  # ---------------------------------------------------------------------------

  describe "constant getters" do
    test "listen_address is 0.0.0.0 (IPv4 wildcard for sibling-container scrapes)" do
      assert Config.listen_address() == "0.0.0.0"
    end

    test "node_exporter_binary path matches the container install location" do
      assert Config.node_exporter_binary() == "/usr/local/bin/node_exporter"
    end

    test "wireguard_exporter_binary path matches the container install location" do
      assert Config.wireguard_exporter_binary() ==
               "/usr/local/bin/prometheus_wireguard_exporter"
    end

    test "host_proc_path / host_sys_path / host_root_path match the bind-mount layout" do
      # node_exporter reads host metrics from these paths via the container's
      # bind mount. Drift here means metrics report container values, not host.
      assert Config.host_proc_path() == "/host/proc"
      assert Config.host_sys_path() == "/host/sys"
      assert Config.host_root_path() == "/host"
    end
  end

  # ---------------------------------------------------------------------------
  # build_config/0 — snapshot map used by the GenServer
  # ---------------------------------------------------------------------------

  describe "build_config/0" do
    test "produces every documented field" do
      result = Config.build_config()

      assert result |> Map.keys() |> Enum.sort() == [
               :host_metrics_port,
               :host_proc_path,
               :host_root_path,
               :host_sys_path,
               :listen_address,
               :node_exporter_binary,
               :wireguard_exporter_binary,
               :wireguard_metrics_port
             ]
    end

    test "ports come from app env" do
      original_host = Elixir.Application.get_env(:edge_agent, :host_metrics_port)
      original_wg = Elixir.Application.get_env(:edge_agent, :wireguard_metrics_port)

      Elixir.Application.put_env(:edge_agent, :host_metrics_port, 49_999)
      Elixir.Application.put_env(:edge_agent, :wireguard_metrics_port, 48_888)

      try do
        result = Config.build_config()
        assert result.host_metrics_port == 49_999
        assert result.wireguard_metrics_port == 48_888
      after
        restore(:host_metrics_port, original_host)
        restore(:wireguard_metrics_port, original_wg)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # node_exporter_args/0 — operational pins. The collector exclusions and
  # path overrides are the contract: change one of these and `node_exporter`
  # silently emits the wrong metrics.
  # ---------------------------------------------------------------------------

  describe "node_exporter_args/0" do
    setup do
      original = Elixir.Application.get_env(:edge_agent, :host_metrics_port)
      Elixir.Application.put_env(:edge_agent, :host_metrics_port, 49_100)
      on_exit(fn -> restore(:host_metrics_port, original) end)
      :ok
    end

    test "binds listen address with the configured port" do
      args = Config.node_exporter_args()

      assert "--web.listen-address=0.0.0.0:49100" in args
    end

    test "overrides procfs/sysfs/rootfs to the host bind-mount paths" do
      args = Config.node_exporter_args()

      assert "--path.procfs=/host/proc" in args
      assert "--path.sysfs=/host/sys" in args
      assert "--path.rootfs=/host" in args
    end

    test "excludes container-internal mountpoints from filesystem collector" do
      args = Config.node_exporter_args()

      assert "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)" in args
    end

    test "excludes virtual / bridge / loopback interfaces from netdev collector" do
      args = Config.node_exporter_args()

      assert "--collector.netdev.device-exclude=^(veth.*|docker.*|br-.*|lo)$$" in args
    end

    test "disables the IPVS collector (typically empty in our containers)" do
      assert "--no-collector.ipvs" in Config.node_exporter_args()
    end

    test "explicitly enables processes / systemd / tcpstat / wifi collectors" do
      args = Config.node_exporter_args()

      for collector <- ~w(processes systemd tcpstat wifi) do
        assert "--collector.#{collector}" in args,
               "expected --collector.#{collector} in node_exporter args"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # wireguard_exporter_args/0 — IPv6 binding is intentional (dual-stack);
  # the four boolean flags drive what the exporter publishes per peer.
  # ---------------------------------------------------------------------------

  describe "wireguard_exporter_args/0" do
    setup do
      original = Elixir.Application.get_env(:edge_agent, :wireguard_metrics_port)
      Elixir.Application.put_env(:edge_agent, :wireguard_metrics_port, 49_586)
      on_exit(fn -> restore(:wireguard_metrics_port, original) end)
      :ok
    end

    test "passes the configured port" do
      args = Config.wireguard_exporter_args()
      port_idx = Enum.find_index(args, &(&1 == "--port"))

      assert port_idx
      assert Enum.at(args, port_idx + 1) == "49586"
    end

    test "binds to :: (IPv6 unspecified, dual-stack)" do
      args = Config.wireguard_exporter_args()
      addr_idx = Enum.find_index(args, &(&1 == "--address"))

      assert addr_idx
      assert Enum.at(args, addr_idx + 1) == "::"
    end

    test "enables verbose, separate_allowed_ips, export_remote_ip_and_port, export_latest_handshake_delay" do
      args = Config.wireguard_exporter_args()

      for flag <- ~w(--verbose --separate_allowed_ips --export_remote_ip_and_port --export_latest_handshake_delay) do
        idx = Enum.find_index(args, &(&1 == flag))
        assert idx != nil, "expected #{flag} to be present"
        assert Enum.at(args, idx + 1) == "true"
      end
    end
  end

  # ---------------------------------------------------------------------------

  defp restore(key, nil), do: Elixir.Application.delete_env(:edge_agent, key)
  defp restore(key, value), do: Elixir.Application.put_env(:edge_agent, key, value)
end
