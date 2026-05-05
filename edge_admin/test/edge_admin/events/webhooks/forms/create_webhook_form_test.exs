# edge_admin/test/edge_admin/events/webhooks/forms/create_webhook_form_test.exs
defmodule EdgeAdmin.Events.Webhooks.Forms.CreateWebhookFormTest do
  # async: false — the form's URL validator runs SSRF, which reads the
  # `:webhook_allow_private_ips` application env. We pin it to false here
  # so the deny-list path is exercised regardless of dev/test env defaults.
  use ExUnit.Case, async: false

  alias EdgeAdmin.Events.Webhooks.Forms.CreateWebhookForm

  setup do
    original = Elixir.Application.get_env(:edge_admin, :webhook_allow_private_ips, false)
    Elixir.Application.put_env(:edge_admin, :webhook_allow_private_ips, false)
    on_exit(fn -> Elixir.Application.put_env(:edge_admin, :webhook_allow_private_ips, original) end)
    :ok
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # 203.0.113.0/24 is TEST-NET-3 (RFC 5737) — guaranteed public range, never
  # routed, no DNS lookup. Avoids tying tests to outbound DNS while still
  # passing the SSRF deny list.
  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "url" => "https://203.0.113.10/hook",
        "secret" => String.duplicate("x", 32),
        "event_filters" => ["edge.node.registered"]
      },
      overrides
    )
  end

  describe "changeset/1 — valid cases" do
    test "minimum required fields succeed" do
      assert {:ok, attrs} = CreateWebhookForm.changeset(valid_attrs())
      assert attrs["url"] == "https://203.0.113.10/hook"
    end

    test "headers are accepted" do
      assert {:ok, attrs} =
               CreateWebhookForm.changeset(valid_attrs(%{"headers" => %{"Authorization" => "Bearer xyz"}}))

      assert attrs["headers"] == %{"Authorization" => "Bearer xyz"}
    end

    test "wildcard filter matching the catalog is accepted" do
      assert {:ok, _} = CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => ["edge.node.*"]}))
      assert {:ok, _} = CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => ["*"]}))
    end
  end

  describe "changeset/1 — required fields" do
    test "missing url is rejected" do
      attrs = Map.delete(valid_attrs(), "url")
      assert {:error, changeset} = CreateWebhookForm.changeset(attrs)
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing secret is rejected" do
      attrs = Map.delete(valid_attrs(), "secret")
      assert {:error, changeset} = CreateWebhookForm.changeset(attrs)
      assert %{secret: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing event_filters is rejected" do
      attrs = Map.delete(valid_attrs(), "event_filters")
      assert {:error, changeset} = CreateWebhookForm.changeset(attrs)
      assert %{event_filters: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "changeset/1 — url validation" do
    test "non-http scheme is rejected" do
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"url" => "ftp://example.com/"}))
      assert %{url: [msg]} = errors_on(changeset)
      assert msg =~ "absolute http(s) URL"
    end

    test "missing host is rejected" do
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"url" => "https://"}))
      assert %{url: [_]} = errors_on(changeset)
    end

    test "non-URL string is rejected" do
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"url" => "not a url"}))
      assert %{url: [_]} = errors_on(changeset)
    end
  end

  describe "changeset/1 — secret validation" do
    test "short secret is rejected" do
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"secret" => "tooshort"}))
      assert %{secret: [msg]} = errors_on(changeset)
      assert msg =~ "at least 32 bytes"
    end
  end

  describe "changeset/1 — headers validation" do
    test "non-string values are rejected" do
      assert {:error, changeset} =
               CreateWebhookForm.changeset(valid_attrs(%{"headers" => %{"X-Count" => 5}}))

      assert %{headers: [msg]} = errors_on(changeset)
      assert msg =~ "all keys and values must be strings"
    end
  end

  describe "changeset/1 — event_filters validation" do
    test "empty list is rejected" do
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => []}))
      assert %{event_filters: [msg]} = errors_on(changeset)
      assert msg =~ "at least one pattern"
    end

    test "more than 20 patterns is rejected" do
      patterns = for _ <- 1..21, do: "edge.node.registered"
      assert {:error, changeset} = CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => patterns}))
      assert %{event_filters: [msg]} = errors_on(changeset)
      assert msg =~ "cannot exceed 20"
    end

    test "invalid pattern is rejected with the underlying reason" do
      assert {:error, changeset} =
               CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => ["edge..node"]}))

      assert %{event_filters: [msg]} = errors_on(changeset)
      assert msg =~ "edge..node"
    end

    test "pattern matching no current event type is rejected" do
      assert {:error, changeset} =
               CreateWebhookForm.changeset(valid_attrs(%{"event_filters" => ["edge.unknown.foo"]}))

      assert %{event_filters: [msg]} = errors_on(changeset)
      assert msg =~ "matches no current event type"
    end
  end

  describe "changeset/1 — bad input shape" do
    test "non-map params return a base error" do
      assert {:error, changeset} = CreateWebhookForm.changeset("not a map")
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
