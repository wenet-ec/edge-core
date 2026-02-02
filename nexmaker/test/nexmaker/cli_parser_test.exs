defmodule Nexmaker.CliParserTest do
  use ExUnit.Case, async: true

  alias Nexmaker.CliParser

  describe "parse_list_output/1" do
    test "parses valid network list JSON" do
      output = """
      [
        {
          "network": "cluster-default",
          "node_id": "abc-123",
          "connected": true,
          "ipv4_addr": "10.0.0.1",
          "ipv6_addr": "fd00::1"
        }
      ]
      """

      assert {:ok, networks} = CliParser.parse_list_output(output)
      assert is_list(networks)
      assert length(networks) == 1
      assert %{"network" => "cluster-default"} = hd(networks)
    end

    test "handles 'no such network' message" do
      output = "\nno such network"
      assert {:ok, []} = CliParser.parse_list_output(output)
    end

    test "strips netclient log lines before parsing" do
      output = """
      [netclient] 2026-02-02 03:00:00 Some log message
      [netclient] 2026-02-02 03:00:01 Another log
      [
        {"network": "test", "node_id": "123", "connected": true}
      ]
      """

      assert {:ok, networks} = CliParser.parse_list_output(output)
      assert length(networks) == 1
    end

    test "returns error for invalid JSON" do
      output = "[invalid json"
      assert {:error, _} = CliParser.parse_list_output(output)
    end

    test "returns error when JSON is not an array" do
      output = """
      {"network": "test"}
      """

      assert {:error, :expected_array} = CliParser.parse_list_output(output)
    end
  end

  describe "parse_ping_output/1" do
    test "parses valid ping results JSON" do
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
      assert is_map(results)
      assert Map.has_key?(results, "cluster-default")
      assert [peer | _] = results["cluster-default"]
      assert peer["name"] == "admin-abc"
      assert peer["connected"] == true
    end

    test "handles 'No peers found' message" do
      output = "\nNo peers found"
      assert {:ok, %{}} = CliParser.parse_ping_output(output)
    end

    test "handles 'No peers matched the provided filters' message" do
      output = "\nNo peers matched the provided filters"
      assert {:ok, %{}} = CliParser.parse_ping_output(output)
    end

    test "handles 'Failed to ping peers' error" do
      output = "\nFailed to ping peers: connection refused"
      assert {:error, {:ping_failed, "connection refused"}} = CliParser.parse_ping_output(output)
    end

    test "strips netclient log lines before parsing" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting ping...
      [netclient] 2026-02-02 03:00:01 Pinging peers...
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

    test "ignores bare IPv6 addresses that look like JSON arrays" do
      # This is the actual error case from production
      output = "[2001:df2:9b00:1156:290:27ff:fef8:6bc6]"
      assert {:error, _} = CliParser.parse_ping_output(output)
    end

    test "returns error for invalid ping structure" do
      # Valid JSON but wrong structure
      output = """
      {
        "network": "not-an-array"
      }
      """

      assert {:error, :invalid_ping_structure} = CliParser.parse_ping_output(output)
    end

    test "handles mixed log output with error messages" do
      output = """
      [netclient] 2026-02-02 03:00:00 Starting firewall...
      [netclient] 2026-02-02 03:00:01 Some error occurred
      \nFailed to ping peers: network unreachable
      """

      assert {:error, {:ping_failed, "network unreachable"}} = CliParser.parse_ping_output(output)
    end
  end

  describe "real-world edge cases" do
    test "handles multiline JSON with embedded logs" do
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

    test "handles empty network list with logs" do
      output = """
      [netclient] 2026-02-02 03:00:00 Checking networks...
      []
      """

      assert {:ok, []} = CliParser.parse_list_output(output)
    end

    test "handles bare IPv6 in brackets with other text" do
      output = """
      Some debug output
      [2001:df2:9b00:1156:290:27ff:fef8:6bc6]
      More text here
      """

      # Should fail gracefully, not crash
      assert {:error, _} = CliParser.parse_ping_output(output)
    end
  end
end
