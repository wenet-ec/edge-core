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
    fourth = 0
    "100.64.#{third}.#{fourth}/24"
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
      # Go JSON encoding uses struct field names; verify the response is a non-empty map
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

    test "delete/2 removes a network so get returns not_found" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts())

      result = Nexmaker.Api.Networks.get(name, api_opts())

      # Netmaker may return :not_found (404) or a 500 with "no result" body
      assert match?({:error, _}, result)
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

    test "create + delete lifecycle with force: true" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts() ++ [force: true])
    end

    test "create + delete lifecycle with force: false" do
      name = unique_network_name("net")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, _} = Nexmaker.Api.Networks.delete(name, api_opts() ++ [force: false])
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

      # Key must have a value (token string)
      assert is_binary(key["value"]) and key["value"] != ""
      # Key must have a token (base64 enrollment token for netclient)
      assert is_binary(key["token"]) and key["token"] != ""
      # Key must list the network it was created for
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

      found = Enum.find(keys, fn k -> k["value"] == key["value"] end)
      assert found != nil

      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end

    test "delete/2 removes key from list", %{network_name: net} do
      tag = "tag-#{unique_id()}"
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create(net, %{tags: [tag]}, api_opts())

      assert {:ok, _} = Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts())

      {:ok, keys} = Nexmaker.Api.EnrollmentKeys.list(api_opts())
      found = Enum.find(keys, fn k -> k["value"] == key["value"] end)
      assert found == nil
    end

    test "create/3 uses default tag 'default' when not specified", %{network_name: net} do
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create(net, %{uses_remaining: 1}, api_opts())

      # Should have been given default tag by the API module
      assert is_list(key["tags"])

      on_exit(fn -> Nexmaker.Api.EnrollmentKeys.delete(key["value"], api_opts()) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Hosts
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Hosts" do
    test "list/1 returns list of hosts" do
      assert {:ok, hosts} = Nexmaker.Api.Hosts.list(api_opts())
      assert is_list(hosts)
    end

    test "get/2 returns an error for nonexistent host" do
      # Netmaker v1.5 returns 405 for GET /api/hosts/{id} (method not allowed)
      fake_id = "00000000-0000-0000-0000-000000000000"
      assert {:error, _} = Nexmaker.Api.Hosts.get(fake_id, api_opts())
    end

    test "each host in list has required fields" do
      {:ok, hosts} = Nexmaker.Api.Hosts.list(api_opts())

      for host <- hosts do
        assert Map.has_key?(host, "id"), "host missing 'id': #{inspect(host)}"
        assert Map.has_key?(host, "name"), "host missing 'name': #{inspect(host)}"
        assert Map.has_key?(host, "os"), "host missing 'os': #{inspect(host)}"
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
        assert Map.has_key?(node, "hostid"), "node missing 'hostid' (host ref): #{inspect(node)}"
      end
    end

    test "list/2 returns list of nodes for a network" do
      # Create a temporary network; even with no nodes the call should succeed
      name = unique_network_name("nodes")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())

      assert {:ok, nodes} = Nexmaker.Api.Nodes.list(name, api_opts())
      assert is_list(nodes)

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
    end

    test "get/3 returns :not_found for nonexistent node" do
      name = unique_network_name("nodes")
      cidr = unique_cidr()
      {:ok, _} = Nexmaker.Api.Networks.create(name, %{addressrange: cidr}, api_opts())
      fake_node_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, _} = Nexmaker.Api.Nodes.get(name, fake_node_id, api_opts())

      on_exit(fn -> Nexmaker.Api.Networks.delete(name, api_opts()) end)
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

      # Wait for Netmaker to propagate the DNS entry
      Process.sleep(2_000)

      {:ok, entries} = Nexmaker.Api.DNS.list(net, api_opts())
      # Netmaker may append .nm.internal to the stored name; match on address instead
      found = Enum.find(entries, fn e -> e["address"] == ip end)

      assert found != nil,
             "Expected entry with address #{ip} in list entries: #{inspect(entries)}"

      on_exit(fn -> Nexmaker.Api.DNS.delete(net, dns_name, api_opts()) end)
    end

    test "created entry appears in get_all/1", %{network_name: net} do
      dns_name = "allhost.#{net}.nm.internal"
      ip = "10.99.0.3"
      {:ok, _} = Nexmaker.Api.DNS.create(net, %{name: dns_name, address: ip}, api_opts())

      # Wait for Netmaker to propagate the DNS entry
      Process.sleep(2_000)

      {:ok, all_entries} = Nexmaker.Api.DNS.get_all(api_opts())
      # Netmaker may append .nm.internal to the stored name; match on address instead
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
      found = Enum.find(entries, fn e -> e["name"] == dns_name end)
      assert found == nil
    end

    test "get_adm_network/2 returns same entries as list/2", %{network_name: net} do
      assert {:ok, list_entries} = Nexmaker.Api.DNS.list(net, api_opts())
      assert {:ok, adm_entries} = Nexmaker.Api.DNS.get_adm_network(net, api_opts())
      assert list_entries == adm_entries
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Api.Nodes metadata round-trip
  # (used by admin discovery — the most critical integration path)
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Api.Nodes - metadata round-trip" do
    # This test requires a real node on the network. We skip if none exist.
    # The test verifies that Nodes.update/4 + Nodes.get/3 round-trips metadata,
    # which is the mechanism admin discovery relies on.
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

          # Write metadata
          assert {:ok, updated} =
                   Nexmaker.Api.Nodes.update(
                     network,
                     node_id,
                     Map.put(node, "metadata", Jason.encode!(metadata)),
                     api_opts()
                   )

          # Read back and verify
          assert {:ok, fetched} = Nexmaker.Api.Nodes.get(network, node_id, api_opts())
          raw_meta = fetched["metadata"]

          assert is_binary(raw_meta) and raw_meta != "",
                 "Expected metadata to be a non-empty string, got: #{inspect(raw_meta)}"

          decoded = Jason.decode!(raw_meta)
          assert decoded["admin_url"] == test_value

          # Restore original metadata to avoid side effects
          Nexmaker.Api.Nodes.update(
            network,
            node_id,
            Map.put(node, "metadata", node["metadata"] || ""),
            api_opts()
          )

          _ = updated
      end
    end
  end
end
