# edge_admin/test/edge_admin/events/webhooks/views/webhook_view_test.exs
defmodule EdgeAdmin.Events.Webhooks.Views.WebhookViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Events.Webhooks.Views.WebhookView

  defp webhook_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %Webhook{
      id: "webhook-uuid-1",
      url: "https://example.com/hook",
      secret: "32-bytes-of-shared-secret-stuff!",
      headers: %{"X-Custom" => "value"},
      subscribed_events: ["edge.node.registered", "edge.node.status_changed"],
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      webhook = webhook_fixture()

      result = WebhookView.render(webhook)

      assert result.id == webhook.id
      assert result.url == "https://example.com/hook"
      assert result.subscribed_events == ["edge.node.registered", "edge.node.status_changed"]
      assert result.inserted_at == webhook.inserted_at
      assert result.updated_at == webhook.updated_at
    end

    test "SECURITY: secret is NEVER in the rendered output" do
      # The secret is the HMAC signing key; leaking it lets anyone forge
      # X-Edge-Signature headers. The view enforces non-leakage by simply
      # not including the field. Pin it explicitly.
      webhook = webhook_fixture(%{secret: "leaked-secret-value-do-not-render"})

      result = WebhookView.render(webhook)

      refute Map.has_key?(result, :secret)
      refute result |> inspect() |> String.contains?("leaked-secret-value-do-not-render")
    end

    test "SECURITY: headers are NEVER in the rendered output" do
      # Custom headers can carry credentials (e.g. operator-supplied
      # Authorization). Same pattern as :secret — drop entirely.
      webhook = webhook_fixture(%{headers: %{"Authorization" => "Bearer leaked-bearer-token"}})

      result = WebhookView.render(webhook)

      refute Map.has_key?(result, :headers)
      refute result |> inspect() |> String.contains?("leaked-bearer-token")
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = WebhookView.render(webhook_fixture())

      expected_keys = Enum.sort(~w(id url subscribed_events inserted_at updated_at)a)
      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
