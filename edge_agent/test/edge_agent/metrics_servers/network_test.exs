# edge_agent/test/edge_agent/metrics_servers/network_test.exs
defmodule EdgeAgent.MetricsServers.NetworkTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.MetricsServers.Network

  # ---------------------------------------------------------------------------
  # Realistic `ip addr show` output. Each interface block starts with
  # `<index>: <name>:`. Multi-line indented body follows.
  # ---------------------------------------------------------------------------

  @ip_addr_show """
  1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
      link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
      inet 127.0.0.1/8 scope host lo
         valid_lft forever preferred_lft forever
  2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
      link/ether de:ad:be:ef:00:01 brd ff:ff:ff:ff:ff:ff
      inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic eth0
         valid_lft 86400sec preferred_lft 86400sec
  3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
      link/ether 02:42:11:22:33:44 brd ff:ff:ff:ff:ff:ff
      inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
         valid_lft forever preferred_lft forever
  4: wg-cluster-a: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default
      link/none
      inet 100.64.0.5/24 scope global wg-cluster-a
         valid_lft forever preferred_lft forever
  5: br-abc123: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
      link/ether 02:42:aa:bb:cc:dd brd ff:ff:ff:ff:ff:ff
      inet 172.18.0.1/24 brd 172.18.0.255 scope global br-abc123
         valid_lft forever preferred_lft forever
  6: veth0a1b2c3@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master docker0 state UP group default
      link/ether ee:ff:00:11:22:33 brd ff:ff:ff:ff:ff:ff
  """

  # ---------------------------------------------------------------------------
  # split_into_interfaces/1
  # ---------------------------------------------------------------------------

  describe "split_into_interfaces/1" do
    test "splits ip-addr-show output into one block per interface" do
      blocks = Network.split_into_interfaces(@ip_addr_show)
      assert length(blocks) == 6
    end

    test "each block carries its header line" do
      blocks = Network.split_into_interfaces(@ip_addr_show)

      headers = Enum.map(blocks, fn block -> block |> String.split("\n") |> hd() end)

      assert Enum.at(headers, 0) =~ ~r/^1:\s+lo:/
      assert Enum.at(headers, 1) =~ ~r/^2:\s+eth0:/
      assert Enum.at(headers, 2) =~ ~r/^3:\s+docker0:/
      assert Enum.at(headers, 3) =~ ~r/^4:\s+wg-cluster-a:/
      assert Enum.at(headers, 4) =~ ~r/^5:\s+br-abc123:/
      assert Enum.at(headers, 5) =~ ~r/^6:\s+veth0a1b2c3@if7:/
    end

    test "each block carries its body lines (so first_global_inet can find inet rows)" do
      blocks = Network.split_into_interfaces(@ip_addr_show)
      eth0_block = Enum.at(blocks, 1)

      assert eth0_block =~ "inet 192.168.1.100"
    end

    test "empty input → empty list" do
      assert Network.split_into_interfaces("") == []
    end
  end

  # ---------------------------------------------------------------------------
  # excluded_interface?/1
  # ---------------------------------------------------------------------------

  describe "excluded_interface?/1" do
    test "loopback is excluded" do
      assert Network.excluded_interface?("1: lo: <LOOPBACK,UP,LOWER_UP> ...")
    end

    test "WireGuard interfaces (wg*) are excluded" do
      assert Network.excluded_interface?("4: wg-cluster-a: <POINTOPOINT> ...")
      assert Network.excluded_interface?("4: wg0: ...")
    end

    test "Docker bridges (docker*) are excluded" do
      assert Network.excluded_interface?("3: docker0: ...")
      assert Network.excluded_interface?("3: docker_gwbridge: ...")
    end

    test "user-defined Docker bridges (br-*) are excluded" do
      assert Network.excluded_interface?("5: br-abc123: ...")
    end

    test "veth pairs (veth*) are excluded" do
      assert Network.excluded_interface?("6: veth0a1b2c3@if7: ...")
    end

    test "physical interfaces are NOT excluded" do
      refute Network.excluded_interface?("2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...")
      refute Network.excluded_interface?("2: enp3s0: ...")
      refute Network.excluded_interface?("2: ens18: ...")
      refute Network.excluded_interface?("2: wlan0: ...")
    end

    test "malformed block (no header) → not excluded (catch-all returns false)" do
      refute Network.excluded_interface?("not an interface block")
      refute Network.excluded_interface?("")
    end
  end

  # ---------------------------------------------------------------------------
  # extract_ip_from_line/1 — only `scope global` IPv4, not loopback
  # ---------------------------------------------------------------------------

  describe "extract_ip_from_line/1" do
    test "returns the IPv4 from a global-scope inet line" do
      line = "    inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic eth0"
      assert Network.extract_ip_from_line(line) == "192.168.1.100"
    end

    test "returns nil for host-scope (loopback) lines" do
      line = "    inet 127.0.0.1/8 scope host lo"
      assert Network.extract_ip_from_line(line) == nil
    end

    test "explicitly returns nil for 127.0.0.1 even if line says scope global (defensive)" do
      # Documents the explicit guard. Nothing in practice tags 127.0.0.1 as
      # global, but the explicit check survives unusual configs.
      line = "    inet 127.0.0.1/8 brd 127.255.255.255 scope global lo"
      assert Network.extract_ip_from_line(line) == nil
    end

    test "non-inet lines return nil" do
      assert Network.extract_ip_from_line("    link/ether de:ad:be:ef:00:01 brd ff:ff:ff:ff:ff:ff") == nil
      assert Network.extract_ip_from_line("       valid_lft 86400sec preferred_lft 86400sec") == nil
    end

    test "IPv6 (inet6) lines return nil" do
      assert Network.extract_ip_from_line("    inet6 fe80::dead:beef/64 scope link") == nil
    end

    test "empty line returns nil" do
      assert Network.extract_ip_from_line("") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # first_global_inet/1
  # ---------------------------------------------------------------------------

  describe "first_global_inet/1" do
    test "returns the global-scope IPv4 from an interface block" do
      block = """
      2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
          link/ether de:ad:be:ef:00:01 brd ff:ff:ff:ff:ff:ff
          inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic eth0
             valid_lft 86400sec preferred_lft 86400sec
      """

      assert Network.first_global_inet(block) == "192.168.1.100"
    end

    test "returns nil for a block with no global-scope inet line (e.g. lo)" do
      block = """
      1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
          link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
          inet 127.0.0.1/8 scope host lo
             valid_lft forever preferred_lft forever
      """

      assert Network.first_global_inet(block) == nil
    end

    test "returns nil for a block with no inet line at all (e.g. veth)" do
      block = """
      6: veth0a1b2c3@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master docker0 state UP group default
          link/ether ee:ff:00:11:22:33 brd ff:ff:ff:ff:ff:ff
      """

      assert Network.first_global_inet(block) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: filtering an `ip addr show` snapshot picks only the eth0 IP
  # ---------------------------------------------------------------------------

  describe "filtering pipeline (split → reject → first_global_inet)" do
    test "selects the physical-interface IP from a realistic snapshot" do
      result =
        @ip_addr_show
        |> Network.split_into_interfaces()
        |> Enum.reject(&Network.excluded_interface?/1)
        |> Enum.find_value(&Network.first_global_inet/1)

      # eth0 is the only non-excluded interface with a global-scope inet.
      # docker0 / br-abc123 also have global inet, but they're excluded by
      # name; wg-cluster-a is excluded too.
      assert result == "192.168.1.100"
    end
  end
end
