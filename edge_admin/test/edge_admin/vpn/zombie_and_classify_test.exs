# edge_admin/test/edge_admin/vpn/zombie_and_classify_test.exs
defmodule EdgeAdmin.Vpn.ZombieAndClassifyTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Vpn

  # ---------------------------------------------------------------------------
  # zombie_node?/4
  # ---------------------------------------------------------------------------

  defp node_with(host_id, lastcheckin) do
    %{"id" => "node-#{host_id}", "hostid" => host_id, "lastcheckin" => lastcheckin}
  end

  describe "zombie_node?/4" do
    test "fresh check-in is never a zombie" do
      now = 1_700_000_000
      node = node_with("h1", now - 10)

      refute Vpn.zombie_node?(node, now, 120, [])
    end

    test "check-in older than threshold and unprotected → zombie" do
      now = 1_700_000_000
      node = node_with("h1", now - 200)

      assert Vpn.zombie_node?(node, now, 120, [])
    end

    test "check-in exactly at threshold is NOT a zombie (strict greater-than)" do
      now = 1_700_000_000
      node = node_with("h1", now - 120)

      refute Vpn.zombie_node?(node, now, 120, [])
    end

    test "protected hosts are never reaped, even when long-stale" do
      # Critical safety property: a live admin briefly behind on check-in
      # must not be deleted just because syn says it's a current member.
      now = 1_700_000_000
      node = node_with("h1", now - 100_000)

      refute Vpn.zombie_node?(node, now, 120, ["h1"])
    end

    test "protection only matches by host id, not arbitrary other ids" do
      now = 1_700_000_000
      node = node_with("h1", now - 200)

      assert Vpn.zombie_node?(node, now, 120, ["other-host"])
    end

    test "accepts a MapSet for the protected set" do
      now = 1_700_000_000
      node = node_with("h1", now - 100_000)

      refute Vpn.zombie_node?(node, now, 120, MapSet.new(["h1", "h2"]))
    end

    test "future-dated check-in (clock skew) yields negative age, never a zombie" do
      now = 1_700_000_000
      node = node_with("h1", now + 60)

      refute Vpn.zombie_node?(node, now, 120, [])
    end
  end

  # ---------------------------------------------------------------------------
  # classify_create_network_400/1
  # ---------------------------------------------------------------------------

  describe "classify_create_network_400/1" do
    test "CIDR collision → :already_exists" do
      body = %{"Message" => "network cidr already in use by network-foo"}
      assert Vpn.classify_create_network_400(body) == {:error, :already_exists}
    end

    test "name collision (Netmaker phrasing: 'invalid network name') → :already_exists" do
      body = %{"Message" => "invalid network name: already exists"}
      assert Vpn.classify_create_network_400(body) == {:error, :already_exists}
    end

    test "substring match — phrase can appear anywhere in the message" do
      body = %{"Message" => "validation failed: network cidr already in use, retry"}
      assert Vpn.classify_create_network_400(body) == {:error, :already_exists}
    end

    test "matching is case-sensitive — wrong case falls through" do
      # Documents actual behaviour. Netmaker uses lowercase consistently;
      # if it ever changes, this test surfaces it before users hit it.
      body = %{"Message" => "Network CIDR already in use"}
      assert Vpn.classify_create_network_400(body) == {:error, :service_unavailable}
    end

    test "unknown 400 message → :service_unavailable" do
      body = %{"Message" => "some other error"}
      assert Vpn.classify_create_network_400(body) == {:error, :service_unavailable}
    end

    test "binary body is treated as the message directly" do
      assert Vpn.classify_create_network_400("network cidr already in use") ==
               {:error, :already_exists}
    end

    test "empty / unrecognised body shape → :service_unavailable" do
      assert Vpn.classify_create_network_400(%{}) == {:error, :service_unavailable}
      assert Vpn.classify_create_network_400(nil) == {:error, :service_unavailable}
      assert Vpn.classify_create_network_400("") == {:error, :service_unavailable}
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_netmaker_error/1
  # ---------------------------------------------------------------------------

  describe "normalize_netmaker_error/1" do
    # Inputs are whatever Nexmaker.Api.normalize/1 returns. We don't mock it —
    # we just feed pre-normalised shapes and verify the funnel collapses
    # correctly. The contract is: ok stays ok, :not_found is preserved,
    # everything else becomes :service_unavailable.

    test "ok tuple is preserved" do
      # Any value works because the funnel doesn't inspect it.
      assert Vpn.normalize_netmaker_error({:ok, %{"netid" => "x"}}) == {:ok, %{"netid" => "x"}}
      assert Vpn.normalize_netmaker_error({:ok, []}) == {:ok, []}
    end

    test ":not_found is preserved (so callers can render 404)" do
      # Api.normalize already produces {:error, :not_found} for 404s; we just
      # have to make sure the funnel doesn't flatten it into :service_unavailable.
      assert Vpn.normalize_netmaker_error({:error, :not_found}) == {:error, :not_found}
    end

    test "every other error collapses to :service_unavailable" do
      assert Vpn.normalize_netmaker_error({:error, :timeout}) == {:error, :service_unavailable}
      assert Vpn.normalize_netmaker_error({:error, :econnrefused}) == {:error, :service_unavailable}
      assert Vpn.normalize_netmaker_error({:error, %{status: 500}}) == {:error, :service_unavailable}
      assert Vpn.normalize_netmaker_error({:error, "anything"}) == {:error, :service_unavailable}
    end

    test "narrows Api.normalize — :conflict and {:bad_request, _} both flatten" do
      # Api.normalize/1 preserves :conflict and {:bad_request, _}, but the Vpn
      # funnel intentionally only surfaces :not_found. Pin the narrowing so a
      # later refactor can't widen the funnel without updating callers.
      assert Vpn.normalize_netmaker_error({:error, :conflict}) == {:error, :service_unavailable}

      assert Vpn.normalize_netmaker_error({:error, {:bad_request, %{"Message" => "x"}}}) ==
               {:error, :service_unavailable}
    end
  end
end
