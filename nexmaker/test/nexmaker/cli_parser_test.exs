defmodule Nexmaker.CliParserTest do
  use ExUnit.Case, async: true

  alias Nexmaker.CliParser

  # ===========================================================================
  # parse_list_output/1
  # ===========================================================================

  describe "parse_list_output/1 - happy path" do
    test "parses single network" do
      output = """
      [
        {
          "network": "cluster-default",
          "node_id": "abc-123",
          "connected": true,
          "ipv4_addr": "10.0.0.1/24",
          "ipv6_addr": "fd00::1"
        }
      ]
      """

      assert {:ok, [network]} = CliParser.parse_list_output(output)
      assert network["network"] == "cluster-default"
      assert network["node_id"] == "abc-123"
      assert network["connected"] == true
      assert network["ipv4_addr"] == "10.0.0.1/24"
      assert network["ipv6_addr"] == "fd00::1"
    end

    test "parses multiple networks" do
      output = """
      [
        {"network": "cluster-a", "node_id": "id-1", "connected": true, "ipv4_addr": "10.0.0.1/24", "ipv6_addr": ""},
        {"network": "cluster-b", "node_id": "id-2", "connected": false, "ipv4_addr": "10.0.0.2/24", "ipv6_addr": ""}
      ]
      """

      assert {:ok, networks} = CliParser.parse_list_output(output)
      assert length(networks) == 2
      assert Enum.at(networks, 0)["network"] == "cluster-a"
      assert Enum.at(networks, 1)["network"] == "cluster-b"
    end

    test "parses empty JSON array as empty list" do
      assert {:ok, []} = CliParser.parse_list_output("[]")
    end

    test "parses compact (no whitespace) JSON" do
      output =
        ~s([{"network":"x","node_id":"1","connected":true,"ipv4_addr":"10.0.0.1/24","ipv6_addr":""}])

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == "x"
    end

    test "strips leading [netclient] log lines before JSON" do
      output = """
      [netclient] 2026-02-02 03:00:00 Some log message
      [netclient] 2026-02-02 03:00:01 Another log
      [
        {"network": "test", "node_id": "123", "connected": true, "ipv4_addr": "10.1.0.1/24", "ipv6_addr": ""}
      ]
      """

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == "test"
    end

    test "strips trailing [netclient] log lines after JSON" do
      output = """
      [
        {"network": "test", "node_id": "123", "connected": true, "ipv4_addr": "10.1.0.1/24", "ipv6_addr": ""}
      ]
      [netclient] 2026-02-02 03:00:02 Done listing
      """

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == "test"
    end

    test "strips [netclient] logs surrounding empty array" do
      output = """
      [netclient] 2026-02-02 03:00:00 Checking networks...
      []
      """

      assert {:ok, []} = CliParser.parse_list_output(output)
    end

    test "preserves connected: false" do
      output = ~s([{"network":"x","node_id":"1","connected":false,"ipv4_addr":"","ipv6_addr":""}])
      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["connected"] == false
    end

    test "handles network with empty ipv6_addr" do
      output =
        ~s([{"network":"x","node_id":"1","connected":true,"ipv4_addr":"10.0.0.5/24","ipv6_addr":""}])

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["ipv6_addr"] == ""
    end
  end

  describe "parse_list_output/1 - no-network plain-text patterns" do
    test "handles bare 'no such network'" do
      assert {:ok, []} = CliParser.parse_list_output("\nno such network")
    end

    test "handles 'no such network' with surrounding whitespace" do
      assert {:ok, []} = CliParser.parse_list_output("  no such network  ")
    end

    test "handles 'no such network' case-insensitively" do
      assert {:ok, []} = CliParser.parse_list_output("No Such Network")
    end

    test "handles 'no such network' embedded in log output" do
      output = """
      [netclient] 2026-02-02 03:00:00 list called
      no such network
      """

      assert {:ok, []} = CliParser.parse_list_output(output)
    end
  end

  describe "parse_list_output/1 - error cases" do
    test "returns error for invalid JSON" do
      assert {:error, _} = CliParser.parse_list_output("[invalid json")
    end

    test "returns error when JSON root is an object not array" do
      # extract_and_parse_json looks for '[' arrays; a bare object returns :no_array_found
      assert {:error, _} = CliParser.parse_list_output(~s({"network":"test"}))
    end

    test "returns error for JSON string scalar" do
      assert {:error, _} = CliParser.parse_list_output(~s("just a string"))
    end

    test "returns error for completely empty string" do
      assert {:error, _} = CliParser.parse_list_output("")
    end

    test "returns error for whitespace-only string" do
      assert {:error, _} = CliParser.parse_list_output("   \n  ")
    end
  end

  # ===========================================================================
  # parse_ping_output/1
  # ===========================================================================

  describe "parse_ping_output/1 - happy path" do
    test "parses single network with one peer" do
      output = """
      {
        "cluster-default": [
          {
            "network": "cluster-default",
            "name": "admin-abc",
            "address": "10.0.0.2",
            "is_extclient": false,
            "connected": true,
            "latency_ms": 25
          }
        ]
      }
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert Map.has_key?(results, "cluster-default")
      assert [peer] = results["cluster-default"]
      assert peer["name"] == "admin-abc"
      assert peer["address"] == "10.0.0.2"
      assert peer["connected"] == true
      assert peer["latency_ms"] == 25
    end

    test "parses multiple networks" do
      output = """
      {
        "cluster-a": [
          {"network": "cluster-a", "name": "node-1", "address": "10.0.0.1", "connected": true, "latency_ms": 10}
        ],
        "cluster-b": [
          {"network": "cluster-b", "name": "node-2", "address": "10.0.1.1", "connected": false, "latency_ms": 999}
        ]
      }
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert map_size(results) == 2
      assert results["cluster-a"] |> hd() |> Map.get("connected") == true
      assert results["cluster-b"] |> hd() |> Map.get("connected") == false
    end

    test "parses multiple peers in one network" do
      output = """
      {
        "cluster-abc": [
          {"network": "cluster-abc", "name": "admin-xyz", "address": "10.1.2.3", "connected": true, "latency_ms": 15},
          {"network": "cluster-abc", "name": "node-123", "address": "10.1.2.4", "connected": false, "latency_ms": 999}
        ]
      }
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert length(results["cluster-abc"]) == 2
    end

    test "strips [netclient] log lines before JSON" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting ping...
      [netclient] 2026-02-02 03:00:01 Pinging peers...
      {
        "test-net": [
          {"network": "test-net", "name": "peer1", "address": "10.0.0.1", "connected": true, "latency_ms": 10}
        ]
      }
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert Map.has_key?(results, "test-net")
    end

    test "strips [netclient] log lines after JSON" do
      output = """
      {
        "test-net": [
          {"network": "test-net", "name": "peer1", "address": "10.0.0.1", "connected": true, "latency_ms": 10}
        ]
      }
      [netclient] 2026-02-02 03:00:02 Ping complete
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert Map.has_key?(results, "test-net")
    end

    test "strips logs both before and after JSON (real-world nftables output)" do
      output = """
      [netclient] 2026-02-02 02:50:53 Starting firewall...
      [netclient] 2026-02-02 02:50:53 using nftables to manage firewall rules...
      {
        "cluster-abc": [
          {
            "network": "cluster-abc",
            "name": "admin-xyz",
            "address": "10.1.2.3",
            "is_extclient": false,
            "connected": true,
            "latency_ms": 15
          },
          {
            "network": "cluster-abc",
            "name": "node-123",
            "address": "10.1.2.4",
            "is_extclient": false,
            "connected": false,
            "latency_ms": 999
          }
        ]
      }
      [netclient] 2026-02-02 02:50:55 Ping completed
      """

      assert {:ok, results} = CliParser.parse_ping_output(output)
      assert Map.has_key?(results, "cluster-abc")
      assert length(results["cluster-abc"]) == 2
    end

    test "preserves is_extclient field" do
      output = """
      {
        "net": [{"network":"net","name":"ext","address":"1.2.3.4","is_extclient":true,"connected":true,"latency_ms":5}]
      }
      """

      assert {:ok, %{"net" => [peer]}} = CliParser.parse_ping_output(output)
      assert peer["is_extclient"] == true
    end

    test "preserves latency_ms of 0" do
      output = """
      {"net":[{"network":"net","name":"p","address":"1.2.3.4","connected":true,"latency_ms":0}]}
      """

      assert {:ok, %{"net" => [peer]}} = CliParser.parse_ping_output(output)
      assert peer["latency_ms"] == 0
    end
  end

  describe "parse_ping_output/1 - no-peers plain-text patterns" do
    test "handles 'No peers found'" do
      assert {:ok, %{}} = CliParser.parse_ping_output("\nNo peers found")
    end

    test "handles 'No peers matched the provided filters'" do
      assert {:ok, %{}} = CliParser.parse_ping_output("\nNo peers matched the provided filters")
    end

    test "handles 'No peers found' case-insensitively" do
      assert {:ok, %{}} = CliParser.parse_ping_output("no peers found")
    end

    test "handles 'No peers matched' case-insensitively" do
      assert {:ok, %{}} = CliParser.parse_ping_output("NO PEERS MATCHED")
    end

    test "handles 'No peers found' embedded in log output" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting firewall...
      No peers found
      """

      assert {:ok, %{}} = CliParser.parse_ping_output(output)
    end
  end

  describe "parse_ping_output/1 - error patterns" do
    test "handles 'Failed to ping peers' with reason" do
      assert {:error, {:ping_failed, "connection refused"}} =
               CliParser.parse_ping_output("\nFailed to ping peers: connection refused")
    end

    test "extracts reason after 'Failed to ping peers:'" do
      assert {:error, {:ping_failed, "network unreachable"}} =
               CliParser.parse_ping_output("\nFailed to ping peers: network unreachable")
    end

    test "handles 'Failed to ping peers' case-insensitively" do
      assert {:error, {:ping_failed, "timeout"}} =
               CliParser.parse_ping_output("failed to ping peers: timeout")
    end

    test "handles 'Failed to ping peers' embedded in log output" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting firewall...
      [netclient] 2026-02-02 03:00:01 Some error occurred
      \nFailed to ping peers: network unreachable
      """

      assert {:error, {:ping_failed, "network unreachable"}} = CliParser.parse_ping_output(output)
    end

    test "trims whitespace from extracted error reason" do
      assert {:error, {:ping_failed, "connection refused"}} =
               CliParser.parse_ping_output("Failed to ping peers:   connection refused  \n")
    end
  end

  describe "parse_ping_output/1 - structure validation" do
    test "rejects JSON object where network value is not a list" do
      output = ~s({"network": "not-an-array"})
      assert {:error, :invalid_ping_structure} = CliParser.parse_ping_output(output)
    end

    test "rejects peer missing 'name' key" do
      output = ~s({"net":[{"address":"1.2.3.4","connected":true}]})
      assert {:error, :invalid_ping_structure} = CliParser.parse_ping_output(output)
    end

    test "rejects peer missing 'address' key" do
      output = ~s({"net":[{"name":"peer","connected":true}]})
      assert {:error, :invalid_ping_structure} = CliParser.parse_ping_output(output)
    end

    test "rejects peer missing 'connected' key" do
      output = ~s({"net":[{"name":"peer","address":"1.2.3.4"}]})
      assert {:error, :invalid_ping_structure} = CliParser.parse_ping_output(output)
    end

    test "bare IPv6 address in brackets is rejected gracefully" do
      output = "[2001:df2:9b00:1156:290:27ff:fef8:6bc6]"
      assert {:error, _} = CliParser.parse_ping_output(output)
    end

    test "bare IPv6 with surrounding text is rejected gracefully" do
      output = """
      Some debug output
      [2001:df2:9b00:1156:290:27ff:fef8:6bc6]
      More text here
      """

      assert {:error, _} = CliParser.parse_ping_output(output)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = CliParser.parse_ping_output("{invalid json")
    end

    test "returns error for JSON array at root (not object)" do
      # Arrays are not valid ping output root
      assert {:error, _} = CliParser.parse_ping_output("[]")
    end

    test "returns error for empty string" do
      assert {:error, _} = CliParser.parse_ping_output("")
    end
  end

  # ===========================================================================
  # parse_peers_output/1
  # ===========================================================================

  describe "parse_peers_output/1 - happy path" do
    test "parses valid peers JSON with interface and peers keys" do
      output = """
      {
        "interface": {"name": "nm-0", "public_key": "abc123"},
        "peers": {
          "cluster-default": [
            {"public_key": "xyz", "endpoint": "1.2.3.4:51820", "allowed_ips": ["10.0.0.2/32"]}
          ]
        }
      }
      """

      assert {:ok, data} = CliParser.parse_peers_output(output)
      assert Map.has_key?(data, "interface")
      assert Map.has_key?(data, "peers")
      assert data["interface"]["name"] == "nm-0"
      assert map_size(data["peers"]) == 1
    end

    test "parses peers spanning multiple networks" do
      output = """
      {
        "interface": {"name": "nm-0"},
        "peers": {
          "cluster-a": [{"public_key": "k1", "endpoint": "1.1.1.1:51820", "allowed_ips": []}],
          "cluster-b": [{"public_key": "k2", "endpoint": "2.2.2.2:51820", "allowed_ips": []}]
        }
      }
      """

      assert {:ok, data} = CliParser.parse_peers_output(output)
      assert map_size(data["peers"]) == 2
    end

    test "strips [netclient] log lines before JSON" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting firewall...
      [netclient] 2026-02-02 03:00:01 Loading peers...
      {"interface":{"name":"nm-0"},"peers":{"net":[{"public_key":"k","endpoint":"1.2.3.4:51820","allowed_ips":[]}]}}
      """

      assert {:ok, data} = CliParser.parse_peers_output(output)
      assert data["interface"]["name"] == "nm-0"
    end
  end

  describe "parse_peers_output/1 - no-peers plain-text patterns" do
    test "handles 'No peers found' message" do
      assert {:ok, %{"peers" => %{}}} = CliParser.parse_peers_output("\nNo peers found")
    end

    test "handles 'No peers found on interface' message" do
      assert {:ok, %{"peers" => %{}}} =
               CliParser.parse_peers_output("\nNo peers found on interface nm-0")
    end

    test "handles empty JSON array (no peers)" do
      assert {:ok, %{"peers" => %{}}} = CliParser.parse_peers_output("[]")
    end

    test "handles '[]' with surrounding whitespace" do
      assert {:ok, %{"peers" => %{}}} = CliParser.parse_peers_output("  []  ")
    end
  end

  describe "parse_peers_output/1 - error patterns" do
    test "handles 'Failed to get peer information' error" do
      assert {:error, {:peers_failed, "connection refused"}} =
               CliParser.parse_peers_output(
                 "\nFailed to get peer information: connection refused"
               )
    end

    test "extracts reason after colon" do
      assert {:error, {:peers_failed, "HTTP 503"}} =
               CliParser.parse_peers_output("Failed to get peer information: HTTP 503")
    end

    test "returns error for JSON missing 'peers' key" do
      output = ~s({"interface": {"name": "nm-0"}})
      assert {:error, :missing_peers_key} = CliParser.parse_peers_output(output)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = CliParser.parse_peers_output("{bad json")
    end

    test "returns error for empty string" do
      assert {:error, _} = CliParser.parse_peers_output("")
    end
  end

  # ===========================================================================
  # JSON extraction edge cases shared across parsers
  # ===========================================================================

  describe "JSON extraction - nested structures" do
    test "handles deeply nested JSON in list output" do
      output = """
      [{"network":"x","node_id":"1","connected":true,"ipv4_addr":"10.0.0.1/24","ipv6_addr":"","meta":{"a":{"b":{"c":1}}}}]
      """

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == "x"
    end

    test "handles JSON with escaped quotes in strings" do
      output = """
      [{"network":"cluster-\\"special\\"","node_id":"1","connected":true,"ipv4_addr":"10.0.0.1/24","ipv6_addr":""}]
      """

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == ~s(cluster-"special")
    end

    test "picks first valid JSON structure when multiple JSON blocks appear in output" do
      # Only the first balanced structure is extracted
      output = """
      [{"network":"first","node_id":"1","connected":true,"ipv4_addr":"10.0.0.1/24","ipv6_addr":""}]
      [{"network":"second","node_id":"2","connected":true,"ipv4_addr":"10.0.0.2/24","ipv6_addr":""}]
      """

      assert {:ok, [net]} = CliParser.parse_list_output(output)
      assert net["network"] == "first"
    end
  end
end
