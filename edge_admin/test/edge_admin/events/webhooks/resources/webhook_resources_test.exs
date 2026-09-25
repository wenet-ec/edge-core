# edge_admin/test/edge_admin/events/webhooks/resources/webhook_resources_test.exs
defmodule EdgeAdmin.Events.Webhooks.Resources.WebhookResourcesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Events.Webhooks.Resources.WebhookResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_webhook!(attrs) do
    Fixtures.insert_webhook!(attrs)
  end

  describe "list/1" do
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
               WebhookResources.list(%{
                 "event_type" => "edge.command_execution.completed",
                 "page" => 1,
                 "page_size" => 20,
                 "sort" => "url"
               })

      assert Enum.map(webhooks, & &1.id) == [matching_a.id, matching_b.id]
      assert meta.total_count == 2
    end
  end
end
