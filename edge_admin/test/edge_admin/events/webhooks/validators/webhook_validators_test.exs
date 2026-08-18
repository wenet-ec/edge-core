# edge_admin/test/edge_admin/events/webhooks/validators/webhook_validators_test.exs
defmodule EdgeAdmin.Events.Webhooks.Validators.WebhookValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Validators.WebhookValidators

  test "validates URL shape without performing network resolution" do
    assert WebhookValidators.url_error("https://example.com/hook") == :ok
    assert {:error, _} = WebhookValidators.url_error("ftp://example.com")
    assert {:error, _} = WebhookValidators.url_error("https://user:pass@example.com")
  end

  test "validates secret and header limits" do
    assert {:error, _} = WebhookValidators.secret_error("short")
    assert WebhookValidators.secret_error(String.duplicate("x", 32)) == :ok
    assert {:error, _} = WebhookValidators.headers_error(%{"X-Test" => 1})
    assert WebhookValidators.headers_error(%{"X-Test" => "ok"}) == :ok
  end

  test "validates subscribed event types" do
    assert WebhookValidators.subscribed_events_error(["edge.node.registered"]) == :ok
    assert {:error, _} = WebhookValidators.subscribed_events_error([])
    assert {:error, message} = WebhookValidators.subscribed_events_error(["edge.unknown.foo"])
    assert message =~ "unknown event type"
  end
end
