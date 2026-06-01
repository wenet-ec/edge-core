# edge_admin/test/edge_admin/events/webhooks/webhooks_test.exs
defmodule EdgeAdmin.Events.WebhooksTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Repo

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

  describe "list_webhooks/1" do
    test "event_type filter applies to both rows and total_count" do
      matching_a =
        insert_webhook!(%{
          subscribed_events: ["edge.command_execution.completed"],
          url: "https://203.0.113.10/a"
        })

      _non_matching =
        insert_webhook!(%{
          subscribed_events: ["edge.node.registered"],
          url: "https://203.0.113.10/b"
        })

      matching_b =
        insert_webhook!(%{
          subscribed_events: ["edge.command_execution.completed", "edge.node.registered"],
          url: "https://203.0.113.10/c"
        })

      assert {:ok, {webhooks, meta}} =
               Webhooks.list_webhooks(%{
                 "event_type" => "edge.command_execution.completed",
                 "page" => 1,
                 "page_size" => 20,
                 "order_by" => "url",
                 "order_directions" => "asc"
               })

      assert Enum.map(webhooks, & &1.id) == [matching_a.id, matching_b.id]
      assert meta.total_count == 2
    end
  end
end
