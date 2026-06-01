# edge_admin/test/edge_admin/events/webhooks/filters/webhook_filters_test.exs
defmodule EdgeAdmin.Events.Webhooks.Filters.WebhookFiltersTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Events.Webhooks.Filters.WebhookFilters
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Repo

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

  defp insert_webhook!(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %Webhook{}
    |> Webhook.changeset(
      Map.merge(
        %{
          url: "https://203.0.113.10/#{System.unique_integer([:positive])}",
          secret: String.duplicate("x", 32),
          subscribed_events: ["edge.node.registered"],
          inserted_at: now,
          updated_at: now
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "filter_by_event_type/2" do
    test "nil → no-op, query returns all rows" do
      a = insert_webhook!(%{subscribed_events: ["edge.node.registered"]})
      b = insert_webhook!(%{subscribed_events: ["edge.node.status_changed"]})

      result =
        Webhook
        |> WebhookFilters.filter_by_event_type(nil)
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert result == Enum.sort([a.id, b.id])
    end

    test "matches only webhooks whose subscribed_events contains the target type" do
      a = insert_webhook!(%{subscribed_events: ["edge.node.registered", "edge.node.status_changed"]})
      _b = insert_webhook!(%{subscribed_events: ["edge.node.status_changed"]})
      c = insert_webhook!(%{subscribed_events: ["edge.node.registered"]})

      result =
        Webhook
        |> WebhookFilters.filter_by_event_type("edge.node.registered")
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert result == Enum.sort([a.id, c.id])
    end

    test "match is exact (no prefix or wildcard semantics)" do
      a = insert_webhook!(%{subscribed_events: ["edge.node.registered"]})
      _b = insert_webhook!(%{subscribed_events: ["edge.node.reregistered"]})

      result =
        Webhook
        |> WebhookFilters.filter_by_event_type("edge.node.reg")
        |> Repo.all()

      assert result == []

      exact_result =
        Webhook
        |> WebhookFilters.filter_by_event_type("edge.node.registered")
        |> Repo.all()
        |> Enum.map(& &1.id)

      assert exact_result == [a.id]
    end
  end
end
