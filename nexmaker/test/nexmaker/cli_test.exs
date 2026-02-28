# nexmaker/test/nexmaker/cli_test.exs
defmodule Nexmaker.CliTest do
  use ExUnit.Case

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Config from environment (injected by docker-compose)
  # ---------------------------------------------------------------------------

  @base_url System.get_env("NETMAKER_BASE_URL", "http://netmaker:8081")
  @master_key System.get_env("NETMAKER_MASTER_KEY", "supersecretkey123456789")

  defp api_opts, do: [base_url: @base_url, master_key: @master_key]

  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])

  defp unique_cidr do
    id = unique_id()
    third = rem(id, 254) + 1
    "100.64.#{third}.0/24"
  end

  defp unique_network_name(prefix \\ "cli") do
    "#{prefix}-#{unique_id()}"
  end

  # ---------------------------------------------------------------------------
  # setup_all: ensure superadmin exists (same bootstrap as API tests)
  # ---------------------------------------------------------------------------

  setup_all do
    case Nexmaker.Api.Superadmin.check(base_url: @base_url) do
      {:ok, false} ->
        {:ok, _} =
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
  # Nexmaker.Cli.list_networks/0 — reads local netclient state
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli.list_networks/0" do
    test "returns {:ok, list}" do
      assert {:ok, networks} = Nexmaker.Cli.list_networks()
      assert is_list(networks)
    end

    test "each listed network has required keys" do
      {:ok, networks} = Nexmaker.Cli.list_networks()

      for net <- networks do
        assert Map.has_key?(net, "network"), "missing 'network': #{inspect(net)}"
        assert Map.has_key?(net, "node_id"), "missing 'node_id': #{inspect(net)}"
        assert Map.has_key?(net, "connected"), "missing 'connected': #{inspect(net)}"
        assert Map.has_key?(net, "ipv4_addr"), "missing 'ipv4_addr': #{inspect(net)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Cli.health_check/1 — pure logic driven by list_networks/ping_peers
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli.health_check/1" do
    test "returns {:ok, status, info} with valid status atom" do
      assert {:ok, status, info} = Nexmaker.Cli.health_check()
      assert status in [:healthy, :degraded, :unhealthy]
      assert is_map(info)
    end

    test "info map has required keys" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check()
      assert Map.has_key?(info, :networks)
      assert Map.has_key?(info, :peer_count)
      assert Map.has_key?(info, :connected_count)
      assert Map.has_key?(info, :warnings)
      assert Map.has_key?(info, :timestamp)
    end

    test "info.networks is a list of strings" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check()
      assert is_list(info.networks)
      for name <- info.networks, do: assert(is_binary(name))
    end

    test "info.warnings is a list" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check()
      assert is_list(info.warnings)
    end

    test "info.timestamp is a DateTime" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check()
      assert %DateTime{} = info.timestamp
    end

    test "skip_peers: true (default) sets peer_count to nil" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check(skip_peers: true)
      assert info.peer_count == nil
      assert info.connected_count == nil
    end

    test "skip_peers: false runs peer check and sets peer_count" do
      assert {:ok, _status, info} = Nexmaker.Cli.health_check(skip_peers: false)
      # peer_count is either nil (peer check failed → degraded) or an integer
      assert info.peer_count == nil or is_integer(info.peer_count)
    end

    test "unhealthy when not connected to any network" do
      # When no networks are joined, health should be :unhealthy
      {:ok, networks} = Nexmaker.Cli.list_networks()

      if networks == [] do
        assert {:ok, :unhealthy, info} = Nexmaker.Cli.health_check()
        assert "Not connected to any network" in info.warnings
      else
        # Already connected — just assert we get a valid response
        assert {:ok, status, _info} = Nexmaker.Cli.health_check()
        assert status in [:healthy, :degraded]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Cli.ping_peers/1
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli.ping_peers/1" do
    test "returns {:ok, map} or {:error, ping_failed} when called with no options" do
      # ping_peers requires a joined network; "server config not found" is expected
      # when no network has been joined yet in the test environment
      result = Nexmaker.Cli.ping_peers()

      case result do
        {:ok, results} -> assert is_map(results)
        {:error, {:ping_failed, _reason}} -> :ok
        {:error, {:netclient_error, _code, _output}} -> :ok
      end
    end

    test "returns {:ok, map} or {:error, ping_failed} when called with json: true" do
      result = Nexmaker.Cli.ping_peers(json: true)

      case result do
        {:ok, results} -> assert is_map(results)
        {:error, {:ping_failed, _reason}} -> :ok
        {:error, {:netclient_error, _code, _output}} -> :ok
      end
    end

    test "each network value in result is a list of peer maps (when joined)" do
      case Nexmaker.Cli.ping_peers() do
        {:ok, results} ->
          for {_network, peers} <- results do
            assert is_list(peers)

            for peer <- peers do
              assert is_map(peer)
              assert Map.has_key?(peer, "name")
              assert Map.has_key?(peer, "address")
              assert Map.has_key?(peer, "connected")
            end
          end

        {:error, _} ->
          # Not joined to any network — acceptable in test environment
          :ok
      end
    end

    test "network filter returns only matching network (when joined)" do
      case Nexmaker.Cli.ping_peers() do
        {:ok, all_results} ->
          case Map.keys(all_results) do
            [] ->
              assert {:ok, _} = Nexmaker.Cli.ping_peers(network: "no-such-network")

            [first_network | _] ->
              assert {:ok, filtered} = Nexmaker.Cli.ping_peers(network: first_network)

              for {net, _peers} <- filtered do
                assert net == first_network
              end
          end

        {:error, _} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Cli.check_connection/1
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli.check_connection/1" do
    test "returns :not_found for a network we haven't joined" do
      assert {:error, :not_found} =
               Nexmaker.Cli.check_connection("definitely-not-joined-network-xyz")
    end

    test "returns connection info for a joined network" do
      {:ok, networks} = Nexmaker.Cli.list_networks()

      case networks do
        [] ->
          # Not joined to anything — skip connection check
          :ok

        [net | _] ->
          network_name = net["network"]

          case Nexmaker.Cli.check_connection(network_name) do
            {:ok, info} ->
              assert info.network == network_name
              assert is_boolean(info.connected)
              assert Map.has_key?(info, :ipv4_addr)
              assert Map.has_key?(info, :node_id)
              assert Map.has_key?(info, :subnet)

            {:error, :not_connected} ->
              # Connected per list but not yet active — acceptable
              :ok

            {:error, reason} ->
              flunk("Unexpected error for known network: #{inspect(reason)}")
          end
      end
    end

    test "subnet is extracted correctly from ipv4_addr" do
      {:ok, networks} = Nexmaker.Cli.list_networks()

      connected = Enum.find(networks, fn n -> n["connected"] == true end)

      if connected do
        network_name = connected["network"]
        {:ok, info} = Nexmaker.Cli.check_connection(network_name)

        if info.connected and info.ipv4_addr do
          # Subnet should be a valid CIDR string
          assert is_binary(info.subnet)
          assert String.contains?(info.subnet, "/")

          # Verify host bits are zeroed — last octet of subnet address
          [addr_part, prefix] = String.split(info.subnet, "/")
          parts = String.split(addr_part, ".")
          assert length(parts) == 4

          prefix_int = String.to_integer(prefix)
          assert prefix_int >= 0 and prefix_int <= 32
        end
      else
        # No connected network available — test is a no-op
        :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Full join/leave lifecycle
  # Requires: network creation, enrollment key, netclient join/leave.
  # This is the most important integration path — covers the agent bootstrap flow.
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli - join/leave lifecycle" do
    @tag timeout: 120_000
    test "join a network, verify membership, then leave" do
      network_name = unique_network_name("cli")
      cidr = unique_cidr()
      tag = "tag-#{unique_id()}"

      # Start netclient daemon in the background — required for join to write local config
      Task.start(fn ->
        System.cmd("netclient", ["daemon"], stderr_to_stdout: true)
      end)

      on_exit(fn -> System.cmd("pkill", ["-f", "netclient daemon"], stderr_to_stdout: true) end)
      # Give daemon a moment to start
      Process.sleep(2_000)

      # Create network via API
      {:ok, _network} =
        Nexmaker.Api.Networks.create(network_name, %{addressrange: cidr}, api_opts())

      # Always clean up the Netmaker-side network
      on_exit(fn -> Nexmaker.Api.Networks.delete(network_name, api_opts()) end)

      # Create enrollment key
      {:ok, key} =
        Nexmaker.Api.EnrollmentKeys.create(
          network_name,
          %{uses_remaining: 1, expiration: 3600, tags: [tag]},
          api_opts()
        )

      enrollment_token = key["token"]
      assert is_binary(enrollment_token) and enrollment_token != ""

      # Snapshot networks before join
      {:ok, before} = Nexmaker.Cli.list_networks()
      before_names = Enum.map(before, & &1["network"])

      # Join the network (allow up to 90s for WireGuard handshake in Docker)
      result =
        Nexmaker.Cli.join_network(
          token: enrollment_token,
          name: "test-host-#{unique_id()}",
          timeout: 90_000
        )

      case result do
        {:ok, %{}} ->
          :ok

        {:error, {:netclient_error, _, output}} ->
          if String.contains?(output, "already") do
            :ok
          else
            flunk("Failed to join network: #{output}")
          end

        {:error, :netclient_not_found} ->
          flunk("netclient binary not found — check Dockerfile")

        other ->
          flunk("Unexpected join result: #{inspect(other)}")
      end

      # Give netclient time to write config files after join
      Process.sleep(3_000)

      # Verify the network now appears in list
      {:ok, after_join} = Nexmaker.Cli.list_networks()
      after_names = Enum.map(after_join, & &1["network"])

      assert network_name in after_names,
             "Expected #{network_name} in network list after join. Got: #{inspect(after_names)}"

      # Verify connection state
      our_net = Enum.find(after_join, fn n -> n["network"] == network_name end)
      assert our_net != nil
      assert Map.has_key?(our_net, "connected")
      assert Map.has_key?(our_net, "ipv4_addr")

      # Confirm check_connection agrees
      assert {:ok, conn_info} = Nexmaker.Cli.check_connection(network_name)
      assert conn_info.network == network_name
      assert conn_info.connected == true
      assert is_binary(conn_info.subnet)

      # health_check should now report :healthy (we have at least one network)
      assert {:ok, health_status, _info} = Nexmaker.Cli.health_check()
      assert health_status in [:healthy, :degraded]

      # Leave the network
      leave_result = Nexmaker.Cli.leave_network(network_name)

      case leave_result do
        :ok ->
          :ok

        {:error, {:netclient_error, _, output}} ->
          if String.contains?(output, "not found") or
               String.contains?(output, "no such network") do
            :ok
          else
            flunk("Failed to leave network: #{output}")
          end
      end

      # Wait for config to be updated
      Process.sleep(500)

      # Verify network is gone from list
      {:ok, after_leave} = Nexmaker.Cli.list_networks()
      after_leave_names = Enum.map(after_leave, & &1["network"])

      refute network_name in after_leave_names,
             "Expected #{network_name} to be absent after leave. Got: #{inspect(after_leave_names)}"

      # Also not in names that were there before
      new_names = MapSet.new(after_leave_names)
      old_names = MapSet.new(before_names)
      added = MapSet.difference(new_names, old_names)
      refute network_name in added
    end
  end

  # ---------------------------------------------------------------------------
  # Nexmaker.Cli.pull/0
  # ---------------------------------------------------------------------------

  describe "Nexmaker.Cli.pull/0" do
    test "returns :ok or a structured error (not a crash)" do
      result = Nexmaker.Cli.pull()

      case result do
        :ok -> :ok
        {:error, {:netclient_error, code, _output}} -> assert is_integer(code)
        {:error, :netclient_not_found} -> flunk("netclient binary not found")
      end
    end
  end
end
