# edge_admin/test/edge_admin/admins/admins_test.exs
defmodule EdgeAdmin.AdminsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Admins

  # ---------------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------------

  defp network(netid, addressrange \\ "100.64.0.0/24") do
    %{"netid" => netid, "addressrange" => addressrange}
  end

  defp member(opts) do
    node = %{
      "address" => Keyword.get(opts, :address, "100.64.0.1/24"),
      "status" => Keyword.get(opts, :status, "online"),
      "lastcheckin" => Keyword.get(opts, :lastcheckin, 1_700_000_000)
    }

    host = %{
      "id" => Keyword.get(opts, :host_id, "host-id-1"),
      "name" => Keyword.fetch!(opts, :name),
      "endpointip" => Keyword.get(opts, :endpointip, "10.0.0.1"),
      "listenport" => Keyword.get(opts, :listenport, 51_820),
      "isstaticport" => Keyword.get(opts, :isstaticport, true)
    }

    %{node: node, host: host}
  end

  defp single_admin(opts) do
    raw = %{
      network: network("admin-cluster-a"),
      members: [member(opts)]
    }

    [admin] = Admins.normalise_cluster(raw).admins
    admin
  end

  # ---------------------------------------------------------------------------
  # normalise_cluster/1
  # ---------------------------------------------------------------------------

  describe "normalise_cluster/1" do
    test "produces the documented admin-domain shape" do
      raw = %{
        network: network("admin-cluster-a", "100.64.0.0/24"),
        members: [member(name: "admin-zzz", host_id: "h1"), member(name: "admin-aaa", host_id: "h2")]
      }

      result = Admins.normalise_cluster(raw)

      assert result.name == "admin-cluster-a"
      assert result.ipv4_range == "100.64.0.0/24"
      assert result.admin_count == 2
      assert is_list(result.admins)
      assert length(result.admins) == 2
    end

    test "sorts admins by name ascending" do
      raw = %{
        network: network("admin-cluster-a"),
        members: [
          member(name: "admin-zzz", host_id: "h1"),
          member(name: "admin-aaa", host_id: "h2"),
          member(name: "admin-mmm", host_id: "h3")
        ]
      }

      result = Admins.normalise_cluster(raw)

      assert Enum.map(result.admins, & &1.name) == ["admin-aaa", "admin-mmm", "admin-zzz"]
    end

    test "admin_count matches the number of normalised admins" do
      raw = %{
        network: network("admin-cluster-a"),
        members: Enum.map(1..5, fn i -> member(name: "admin-#{i}", host_id: "h#{i}") end)
      }

      result = Admins.normalise_cluster(raw)

      assert result.admin_count == length(result.admins)
      assert result.admin_count == 5
    end

    test "empty members list yields admin_count: 0 and admins: []" do
      raw = %{network: network("admin-cluster-a"), members: []}

      result = Admins.normalise_cluster(raw)

      assert result.admin_count == 0
      assert result.admins == []
    end

    test "vpn_hostname is derived from host name + cluster name" do
      raw = %{
        network: network("admin-cluster-a"),
        members: [member(name: "admin-7k3m9p2nq8r4")]
      }

      result = Admins.normalise_cluster(raw)
      [admin] = result.admins

      assert admin.vpn_hostname == "admin-7k3m9p2nq8r4.admin-cluster-a.nm.internal"
    end
  end

  # ---------------------------------------------------------------------------
  # normalise_member field-by-field (exercised through normalise_cluster)
  # ---------------------------------------------------------------------------

  describe "normalise_cluster/1 — per-admin fields" do
    test "passes through name, netmaker_host_id, endpoint, port, status" do
      admin =
        single_admin(
          name: "admin-foo",
          host_id: "f272e703-aaaa-bbbb-cccc-1234",
          endpointip: "10.0.0.7",
          listenport: 51_820,
          status: "online"
        )

      assert admin.name == "admin-foo"
      assert admin.netmaker_host_id == "f272e703-aaaa-bbbb-cccc-1234"
      assert admin.wireguard_ip_address == "10.0.0.7"
      assert admin.wireguard_port == 51_820
      assert admin.status == "online"
    end

    test "strip_cidr removes /prefix from address" do
      admin = single_admin(name: "admin-1", address: "100.64.0.1/24")
      assert admin.ipv4_address == "100.64.0.1"
    end

    test "strip_cidr handles a bare IP without a prefix" do
      admin = single_admin(name: "admin-1", address: "100.64.0.1")
      assert admin.ipv4_address == "100.64.0.1"
    end

    test "strip_cidr passes nil through" do
      admin = single_admin(name: "admin-1", address: nil)
      assert admin.ipv4_address == nil
    end

    test "use_static_port is true only when the raw value is exactly true" do
      assert single_admin(name: "admin-1", isstaticport: true).use_static_port == true
      assert single_admin(name: "admin-1", isstaticport: false).use_static_port == false
      assert single_admin(name: "admin-1", isstaticport: nil).use_static_port == false
      # Defensive: any non-true value coerces to false.
      assert single_admin(name: "admin-1", isstaticport: "true").use_static_port == false
    end

    test "format_checkin renders a positive Unix epoch as ISO 8601" do
      admin = single_admin(name: "admin-1", lastcheckin: 1_700_000_000)
      assert admin.last_checked_in == "2023-11-14T22:13:20Z"
    end

    test "format_checkin returns nil for 0, negatives, and non-integers" do
      assert single_admin(name: "admin-1", lastcheckin: 0).last_checked_in == nil
      assert single_admin(name: "admin-1", lastcheckin: -1).last_checked_in == nil
      assert single_admin(name: "admin-1", lastcheckin: nil).last_checked_in == nil
      assert single_admin(name: "admin-1", lastcheckin: "1700000000").last_checked_in == nil
    end
  end
end
