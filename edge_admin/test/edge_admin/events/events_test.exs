# edge_admin/test/edge_admin/events/events_test.exs
defmodule EdgeAdmin.EventsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  @event_time ~U[2026-01-01 00:00:00Z]
  @envelope_id "00000000-0000-4000-8000-000000000001"

  defp node_event do
    cluster = %Cluster{id: "cluster-uuid-1", name: "prod"}

    node = %Node{
      id: "node-uuid-1",
      cluster: cluster,
      cluster_id: cluster.id,
      status: :healthy,
      version: "1.2.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9101,
      http_proxy_port: 44_001,
      socks5_proxy_port: 44_002,
      self_update_enabled: true,
      api_token: "token",
      proxy_password: "pw",
      enrollment_key_id: "enrollment-key-1",
      vpn_host_id: "h",
      last_seen_at: @event_time,
      inserted_at: @event_time,
      updated_at: @event_time
    }

    %Catalog.NodeRegistered{node: node}
  end

  defp build_envelope(event, corename \\ "default"),
    do: Events.build_envelope(event, @envelope_id, @event_time, corename)

  describe "build_envelope/4" do
    test "produces every documented CloudEvents field" do
      envelope = build_envelope(node_event())

      assert envelope["specversion"] == "1.0"
      assert envelope["source"] == "https://github.com/wenet-ec/edge-core"
      assert envelope["type"] == "edge.node.registered"
      assert envelope["datacontenttype"] == "application/json"
      assert envelope["id"] == @envelope_id
      assert envelope["time"] == DateTime.to_iso8601(@event_time)
      assert envelope["corename"] == "default"
      assert is_map(envelope["data"])
    end

    test "type matches Catalog.event_type/1" do
      event = node_event()
      envelope = build_envelope(event)

      assert envelope["type"] == Catalog.event_type(event)
    end

    test "data matches Catalog.to_data/1" do
      event = node_event()
      envelope = build_envelope(event)

      assert envelope["data"] == Catalog.to_data(event)
    end

    test "includes the provided core name" do
      assert build_envelope(node_event(), "prod-us")["corename"] == "prod-us"
    end

    test "envelope contains exactly the documented top-level keys" do
      envelope = build_envelope(node_event())

      expected_keys =
        Enum.sort(~w(specversion id source type time datacontenttype corename data))

      assert envelope |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
