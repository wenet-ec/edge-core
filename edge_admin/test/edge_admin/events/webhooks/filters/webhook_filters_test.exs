# edge_admin/test/edge_admin/events/webhooks/filters/webhook_filters_test.exs
defmodule EdgeAdmin.Events.Webhooks.Filters.WebhookFiltersTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Filters.WebhookFilters
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  defp webhook(events), do: %Webhook{subscribed_events: events}

  # ---------------------------------------------------------------------------
  # pop_event_type/1 — extracts the event_type filter out of params, accepting
  # only string values (rejects anything else, returns nil + remaining params).
  # ---------------------------------------------------------------------------

  describe "pop_event_type/1" do
    test "returns the string event_type and params without that key" do
      assert WebhookFilters.pop_event_type(%{"event_type" => "edge.node.registered", "page" => 1}) ==
               {"edge.node.registered", %{"page" => 1}}
    end

    test "accepts atom-keyed event_type params from OpenAPI-cast requests" do
      assert WebhookFilters.pop_event_type(%{event_type: "edge.node.registered", page: 1}) ==
               {"edge.node.registered", %{page: 1}}
    end

    test "returns nil and unchanged params when the key is missing" do
      assert WebhookFilters.pop_event_type(%{"page" => 2}) == {nil, %{"page" => 2}}
    end

    test "returns nil when value is missing entirely" do
      assert WebhookFilters.pop_event_type(%{}) == {nil, %{}}
    end

    test "rejects non-binary value (returns nil, drops the key from params)" do
      assert WebhookFilters.pop_event_type(%{"event_type" => 123, "page" => 1}) ==
               {nil, %{"page" => 1}}

      assert WebhookFilters.pop_event_type(%{"event_type" => :registered}) == {nil, %{}}

      assert WebhookFilters.pop_event_type(%{"event_type" => nil, "page" => 1}) ==
               {nil, %{"page" => 1}}
    end
  end

  # ---------------------------------------------------------------------------
  # filter_by_event_type/2 — Elixir-side post-query filter. The same shape is
  # used by Webhooks.fan_out/1, so the two paths can't drift.
  # ---------------------------------------------------------------------------

  describe "filter_by_event_type/2" do
    test "nil → no-op, returns the input list unchanged" do
      webhooks = [webhook(["edge.node.registered"]), webhook(["edge.node.status_changed"])]

      assert WebhookFilters.filter_by_event_type(webhooks, nil) == webhooks
    end

    test "matches webhooks whose subscribed_events contains the target type" do
      a = webhook(["edge.node.registered", "edge.node.status_changed"])
      b = webhook(["edge.node.status_changed"])
      c = webhook(["edge.node.registered"])

      result = WebhookFilters.filter_by_event_type([a, b, c], "edge.node.registered")

      assert result == [a, c]
    end

    test "preserves input order" do
      a = webhook(["edge.node.registered"])
      b = webhook(["edge.command_execution.completed"])
      c = webhook(["edge.node.registered"])
      d = webhook(["edge.node.registered"])

      assert WebhookFilters.filter_by_event_type([a, b, c, d], "edge.node.registered") ==
               [a, c, d]
    end

    test "returns [] when no webhooks match" do
      webhooks = [webhook(["edge.node.registered"]), webhook(["edge.node.status_changed"])]

      assert WebhookFilters.filter_by_event_type(webhooks, "edge.command_execution.completed") ==
               []
    end

    test "empty input list yields empty output regardless of event type" do
      assert WebhookFilters.filter_by_event_type([], "edge.node.registered") == []
    end

    test "match is exact (no prefix or wildcard semantics)" do
      a = webhook(["edge.node.registered"])
      b = webhook(["edge.node.reregistered"])

      # "edge.node.reg" must not match either.
      assert WebhookFilters.filter_by_event_type([a, b], "edge.node.reg") == []

      # Exact match returns just the registered one.
      assert WebhookFilters.filter_by_event_type([a, b], "edge.node.registered") == [a]
    end
  end
end
