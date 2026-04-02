# nexmaker/test/nexmaker/api_test.exs
defmodule Nexmaker.ApiTest do
  use ExUnit.Case

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Shared config from environment (injected by docker-compose)
  # ---------------------------------------------------------------------------

  @base_url System.get_env("NETMAKER_BASE_URL", "http://netmaker:8081")
  @master_key System.get_env("NETMAKER_MASTER_KEY", "supersecretkey123456789")

  defp api_opts, do: [base_url: @base_url, master_key: @master_key]

  # ---------------------------------------------------------------------------
  # Unique ID helpers — avoid CIDR / name collisions across concurrent runs
  # ---------------------------------------------------------------------------

  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  # Produces a /24 in 100.64.x.0/24 range (100.64/10 is IANA Shared Address Space,
  # valid for Netmaker and not routable on the public internet).
  defp unique_cidr do
    id = unique_id()
    third = rem(id, 254) + 1
    "100.64.#{third}.0/24"
  end

  defp unique_network_name(prefix \\ "test") do
    id = unique_id()
    "#{prefix}-#{id}"
  end

  # ---------------------------------------------------------------------------
  # setup_all: ensure superadmin exists once before any API call
  # ---------------------------------------------------------------------------

  setup_all do
    # Netmaker v1.5+ needs a superadmin to activate the server before API calls
    # work with the master key.
    case Nexmaker.Api.Superadmin.check(base_url: @base_url) do
      {:ok, false} ->
        {:ok, _user} =
          Nexmaker.Api.Superadmin.create(
            %{username: "admin", password: "admin123456"},
            base_url: @base_url
          )

      {:ok, true} ->
        :ok

      other ->
        raise "Failed to bootstrap superadmin: #{inspect(other)}"
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Superadmin
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Superadmin" do
    test "check/1 returns a boolean" do
      assert {:ok, value} = Nexmaker.Api.Superadmin.check(base_url: @base_url)
      assert is_boolean(value)
    end

    test "check/1 returns true after setup_all bootstrap" do
      assert {:ok, true} = Nexmaker.Api.Superadmin.check(base_url: @base_url)
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Server
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Server" do
    test "status/1 returns healthy server map" do
      assert {:ok, status} = Nexmaker.Api.Server.status(api_opts())
      assert is_map(status)
      assert Map.has_key?(status, "db_connected")
      assert Map.has_key?(status, "broker_connected")
      assert Map.has_key?(status, "version")
      assert status["db_connected"] == true
      # broker_connected may briefly be false after startup; just verify the key is boolean
      assert is_boolean(status["broker_connected"])
    end

    test "get_server_info/1 returns server info map" do
      assert {:ok, info} = Nexmaker.Api.Server.get_server_info(api_opts())
      assert is_map(info)
      assert map_size(info) > 0
    end

    test "status/1 with retries: 0 returns same result as no retries" do
      assert {:ok, _} = Nexmaker.Api.Server.status(api_opts() ++ [retries: 0])
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Networks
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Networks" do
    test "list/1 returns list of networks" do
      assert {:ok, networks} = Nexmaker.Api.Networks.list(api_opts())
      assert is_list(networks)
    end

    test "create/3 returns network with correct netid" do
      name = unique_network_name("net")
      cidr = unique_cidr()

      assert {:ok, network} =
               Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert network["netid"] == name

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "create/3 sets the addressrange" do
      name = unique_network_name("net")
      cidr = unique_cidr()

      {:ok, network} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      assert network["addressrange"] == cidr

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "get/2 retrieves a created network by name" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, fetched} = Nexmaker.Api.Networks.get(name, api_opts())
      assert fetched["netid"] == name
      assert fetched["addressrange"] == cidr

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "get/2 returns :not_found for nonexistent network" do
      assert {:error, :not_found} =
               Nexmaker.Api.Networks.get("does-not-exist-at-all", api_opts())
    end

    test "delete/2 removes a network so get returns error" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts())
      assert match?({:error, _}, Nexmaker.Api.Networks.get(name, api_opts()))
    end

    test "created network appears in list/1" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      {:ok, networks} = Nexmaker.Api.Networks.list(api_opts())
      names = Enum.map(networks, & &1["netid"])
      assert name in names

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "deleted network no longer appears in list/1" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts())

      {:ok, networks} = Nexmaker.Api.Networks.list(api_opts())
      names = Enum.map(networks, & &1["netid"])
      refute name in names
    end

    test "delete/2 with force: true" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts() ++ [force: true])
    end

    test "delete/2 with force: false" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts() ++ [force: false])
    end

    test "stats/1 returns a map" do
      assert {:ok, stats} = Nexmaker.Api.Networks.stats(api_opts())
      assert is_map(stats)
    end

    test "egress_routes/2 returns a map for an existing network" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, routes} = Nexmaker.Api.Networks.egress_routes(name, api_opts())
      # No egress nodes yet — routes is an empty map or nil; either is valid
      assert is_map(routes) or is_nil(routes)

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.EnrollmentKeys
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.EnrollmentKeys" do
    setup do
      name = unique_network_name("enroll")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
      {:ok, network_name: name}
    end

    test "create/3 returns key with required fields", %{network_name: net} do
      tag = "tag-#{unique_id()}"

      assert {:ok, key} =
               Nexmaker.Api.EnrollmentKeys.create(
                 net,
                 %{uses_remaining: 5, expiration: 3600, tags: [tag]},
                 api_opts()
               )

      assert is_binary(key["value"]) and key["value"] != ""
      assert is_binary(key["token"]) and key["token"] != ""
      assert net in key["networks"]

      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end

    test "create/3 with uses_remaining sets usage limit", %{network_name: net} do
      tag = "tag-#{unique_id()}"

      {:ok, key} =
        Nexmaker.Api.EnrollmentKeys.create(
          net,
          %{uses_remaining: 3, tags: [tag]},
          api_opts()
        )

      assert key["uses_remaining"] == 3

      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end

    test "list/1 returns list including created key", %{network_name: net} do
      tag = "tag-#{unique_id()}"
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create(net, %{tags: [tag]}, api_opts())

      assert {:ok, keys} = Nexmaker.Api.EnrollmentKeys.list(api_opts())
      assert is_list(keys)
      assert Enum.any?(keys, fn k -> k["value"] == key["value"] end)

      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end

    test "delete/2 removes key from list", %{network_name: net} do
      tag = "tag-#{unique_id()}"
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create(net, %{tags: [tag]}, api_opts())

      assert {:ok, _} = Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts())

      {:ok, keys} = Nexmaker.Api.EnrollmentKeys.list(api_opts())
      refute Enum.any?(keys, fn k -> k["value"] == key["value"] end)
    end

    test "create/3 assigns tags list", %{network_name: net} do
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create(net, %{uses_remaining: 1}, api_opts())
      assert is_list(key["tags"])
      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Hosts
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Hosts" do
    # list/1 now returns the unwrapped paginated map: %{"data" => [...], "total_pages" => N, ...}
    test "list/1 returns paginated response map" do
      assert {:ok, result} = Nexmaker.Api.Hosts.list(api_opts())
      assert is_map(result)
      assert Map.has_key?(result, "data")
      assert is_list(result["data"])
      assert Map.has_key?(result, "total_pages")
    end

    test "list/1 data entries have required fields" do
      {:ok, %{"data" => hosts}} = Nexmaker.Api.Hosts.list(api_opts())

      for host <- hosts do
        assert Map.has_key?(host, "id"), "host missing 'id': #{inspect(host)}"
        assert Map.has_key?(host, "name"), "host missing 'name': #{inspect(host)}"
        assert Map.has_key?(host, "os"), "host missing 'os': #{inspect(host)}"
      end
    end

    test "list/1 respects per_page option" do
      assert {:ok, result} = Nexmaker.Api.Hosts.list(api_opts() ++ [per_page: 1])
      assert result["per_page"] == 1
    end

    test "get/2 returns :not_found for nonexistent host ID" do
      fake_id = "00000000-0000-0000-0000-000000000000"
      assert {:error, :not_found} = Nexmaker.Api.Hosts.get(fake_id, api_opts())
    end

    test "get/2 returns host when it exists" do
      {:ok, %{"data" => hosts}} = Nexmaker.Api.Hosts.list(api_opts())

      case hosts do
        [] ->
          # No hosts registered yet — skip
          :ok

        [host | _] ->
          assert {:ok, fetched} = Nexmaker.Api.Hosts.get(host["id"], api_opts())
          assert fetched["id"] == host["id"]
          assert fetched["name"] == host["name"]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Nodes
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Nodes" do
    test "list_all/1 returns list of nodes" do
      assert {:ok, nodes} = Nexmaker.Api.Nodes.list_all(api_opts())
      assert is_list(nodes)
    end

    test "each node in list_all has required fields" do
      {:ok, nodes} = Nexmaker.Api.Nodes.list_all(api_opts())

      for node <- nodes do
        assert Map.has_key?(node, "id"), "node missing 'id': #{inspect(node)}"
        assert Map.has_key?(node, "network"), "node missing 'network': #{inspect(node)}"
        assert Map.has_key?(node, "hostid"), "node missing 'hostid': #{inspect(node)}"
      end
    end

    test "list/2 returns list of nodes for a network" do
      name = unique_network_name("nodes")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, nodes} = Nexmaker.Api.Nodes.list(name, api_opts())
      assert is_list(nodes)

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "get/3 returns error for nonexistent node" do
      name = unique_network_name("nodes")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      fake_node_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, _} = Nexmaker.Api.Nodes.get(name, fake_node_id, api_opts())

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "network_status/2 returns a map for an existing network" do
      name = unique_network_name("nodes")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, status} = Nexmaker.Api.Nodes.network_status(name, api_opts())
      # No nodes yet — returns empty map
      assert is_map(status)

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Nodes — metadata round-trip
  # (used by admin discovery — the most critical integration path)
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Nodes - metadata round-trip" do
    test "update metadata on a node and read it back" do
      {:ok, nodes} = Nexmaker.Api.Nodes.list_all(api_opts())

      case nodes do
        [] ->
          # No nodes registered yet — cannot test update round-trip
          :ok

        [node | _] ->
          network = node["network"]
          node_id = node["id"]

          test_value = "test-admin-#{unique_id()}"
          metadata = %{"admin_url" => test_value, "cluster" => "test-cluster"}

          assert {:ok, _updated} =
                   Nexmaker.Api.Nodes.update(
                     network,
                     node_id,
                     Map.put(node, "metadata", Jason.encode!(metadata)),
                     api_opts()
                   )

          assert {:ok, fetched} = Nexmaker.Api.Nodes.get(network, node_id, api_opts())
          raw_meta = fetched["metadata"]

          assert is_binary(raw_meta) and raw_meta != "",
                 "Expected metadata to be a non-empty string, got: #{inspect(raw_meta)}"

          decoded = Jason.decode!(raw_meta)
          assert decoded["admin_url"] == test_value

          # Restore original metadata
          Nexmaker.Api.Nodes.update(
            network,
            node_id,
            Map.put(node, "metadata", node["metadata"] || ""),
            api_opts()
          )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.DNS
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.DNS" do
    setup do
      name = unique_network_name("dns")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
      {:ok, network_name: name}
    end

    test "get_all/1 returns list", %{network_name: _net} do
      assert {:ok, entries} = Nexmaker.Api.DNS.get_all(api_opts())
      assert is_list(entries)
    end

    test "list/2 returns list for a specific network", %{network_name: net} do
      assert {:ok, entries} = Nexmaker.Api.DNS.list(net, api_opts())
      assert is_list(entries)
    end

    test "create/3 and delete/3 round-trip a DNS entry", %{network_name: net} do
      dns_name = "gateway.#{net}.nm.internal"
      ip = "10.99.0.1"

      assert {:ok, entry} =
               Nexmaker.Api.DNS.create(net, %{name: dns_name, address: ip}, api_opts())

      assert entry["name"] == dns_name
      assert entry["address"] == ip
      assert entry["network"] == net

      assert {:ok, _} = Nexmaker.Api.DNS.delete(net, dns_name, api_opts())
    end

    test "created entry appears in list/2", %{network_name: net} do
      dns_name = "myhost.#{net}.nm.internal"
      ip = "10.99.0.2"
      {:ok, _} = Nexmaker.Api.DNS.create(net, %{name: dns_name, address: ip}, api_opts())

      Process.sleep(2_000)

      {:ok, entries} = Nexmaker.Api.DNS.list(net, api_opts())
      found = Enum.find(entries, fn e -> e["address"] == ip end)

      assert found != nil,
             "Expected entry with address #{ip} in list entries: #{inspect(entries)}"

      on_exit(fn -> Nexmaker.Api.DNS.delete(net, dns_name, api_opts()) end)
    end

    test "created entry appears in get_all/1", %{network_name: net} do
      dns_name = "allhost.#{net}.nm.internal"
      ip = "10.99.0.3"
      {:ok, _} = Nexmaker.Api.DNS.create(net, %{name: dns_name, address: ip}, api_opts())

      Process.sleep(2_000)

      {:ok, all_entries} = Nexmaker.Api.DNS.get_all(api_opts())
      found = Enum.find(all_entries, fn e -> e["address"] == ip end)

      assert found != nil,
             "Expected entry with address #{ip} in get_all entries: #{inspect(all_entries)}"

      on_exit(fn -> Nexmaker.Api.DNS.delete(net, dns_name, api_opts()) end)
    end

    test "deleted entry no longer appears in list/2", %{network_name: net} do
      dns_name = "gone.#{net}.nm.internal"
      ip = "10.99.0.4"
      {:ok, _} = Nexmaker.Api.DNS.create(net, %{name: dns_name, address: ip}, api_opts())
      {:ok, _} = Nexmaker.Api.DNS.delete(net, dns_name, api_opts())

      {:ok, entries} = Nexmaker.Api.DNS.list(net, api_opts())
      refute Enum.any?(entries, fn e -> e["name"] == dns_name end)
    end

    test "list_node_entries/2 returns list", %{network_name: net} do
      assert {:ok, entries} = Nexmaker.Api.DNS.list_node_entries(net, api_opts())
      assert is_list(entries)
    end

    test "list_custom_entries/2 returns list", %{network_name: net} do
      assert {:ok, entries} = Nexmaker.Api.DNS.list_custom_entries(net, api_opts())
      assert is_list(entries)
    end
  end
end
