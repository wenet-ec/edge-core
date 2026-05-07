# edge_admin/test/edge_admin/events/events_test.exs
defmodule EdgeAdmin.EventsTest do
  # async: false because tests touch :core_name application env. The envelope
  # builder reads it lazily on every call, so racing test writes would
  # cross-talk between cases.
  use ExUnit.Case, async: false

  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp node_event do
    cluster = %Cluster{id: "cluster-uuid-1", name: "prod"}

    node = %Node{
      id: "node-uuid-1",
      cluster: cluster,
      cluster_id: cluster.id,
      status: "healthy",
      version: "1.2.0",
      id_type: "persistent",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9101,
      http_proxy_port: 44_001,
      socks5_proxy_port: 44_002,
      self_update_enabled: true,
      api_token: "token",
      proxy_password: "pw",
      netmaker_host_id: "h",
      last_seen_at: now(),
      inserted_at: now(),
      updated_at: now()
    }

    %Catalog.NodeRegistered{node: node}
  end

  setup do
    previous = Elixir.Application.get_env(:edge_admin, :core_name)

    on_exit(fn ->
      if is_nil(previous) do
        Elixir.Application.delete_env(:edge_admin, :core_name)
      else
        Elixir.Application.put_env(:edge_admin, :core_name, previous)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # build_envelope/1 — CloudEvents 1.0 envelope shape
  # ---------------------------------------------------------------------------

  describe "build_envelope/1" do
    test "produces every documented CloudEvents field" do
      envelope = Events.build_envelope(node_event())

      assert envelope["specversion"] == "1.0"
      assert envelope["source"] == "https://github.com/wenet-ec/edge-core"
      assert envelope["type"] == "edge.node.registered"
      assert envelope["datacontenttype"] == "application/json"
      assert is_binary(envelope["id"])
      assert is_binary(envelope["time"])
      assert is_binary(envelope["corename"])
      assert is_map(envelope["data"])
    end

    test "id is a fresh UUID per call" do
      e1 = Events.build_envelope(node_event())
      e2 = Events.build_envelope(node_event())

      refute e1["id"] == e2["id"]

      # UUID v4 shape (8-4-4-4-12 hex).
      assert Regex.match?(
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
               e1["id"]
             )
    end

    test "time is a recent ISO 8601 UTC datetime" do
      before = DateTime.utc_now()
      envelope = Events.build_envelope(node_event())
      after_ = DateTime.utc_now()

      {:ok, parsed, _} = DateTime.from_iso8601(envelope["time"])

      assert DateTime.compare(parsed, before) in [:gt, :eq]
      assert DateTime.compare(parsed, after_) in [:lt, :eq]
    end

    test "type matches Catalog.event_type/1" do
      event = node_event()
      envelope = Events.build_envelope(event)

      assert envelope["type"] == Catalog.event_type(event)
    end

    test "data matches Catalog.to_data/1" do
      event = node_event()
      envelope = Events.build_envelope(event)

      assert envelope["data"] == Catalog.to_data(event)
    end

    test "corename comes from :core_name app env" do
      Elixir.Application.put_env(:edge_admin, :core_name, "prod-us")

      assert Events.build_envelope(node_event())["corename"] == "prod-us"
    end

    test "corename defaults to 'default' when :core_name is unset" do
      Elixir.Application.delete_env(:edge_admin, :core_name)

      assert Events.build_envelope(node_event())["corename"] == "default"
    end

    test "envelope contains exactly the documented top-level keys" do
      envelope = Events.build_envelope(node_event())

      expected_keys =
        Enum.sort(~w(specversion id source type time datacontenttype corename data))

      assert envelope |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
