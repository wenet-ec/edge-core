# edge_admin/test/edge_admin/events/webhooks/schemas/webhook_test.exs
defmodule EdgeAdmin.Events.Webhooks.Schemas.WebhookTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        url: "https://example.com/hook",
        secret: String.duplicate("x", 32),
        subscribed_events: ["edge.node.registered"]
      },
      overrides
    )
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid attrs produce a valid changeset" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs())
      assert changeset.valid?
    end

    test "url is required" do
      changeset = Webhook.changeset(%Webhook{}, Map.delete(valid_attrs(), :url))
      refute changeset.valid?
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "secret is required" do
      changeset = Webhook.changeset(%Webhook{}, Map.delete(valid_attrs(), :secret))
      refute changeset.valid?
      assert %{secret: ["can't be blank"]} = errors_on(changeset)
    end

    test "subscribed_events is required" do
      changeset = Webhook.changeset(%Webhook{}, Map.delete(valid_attrs(), :subscribed_events))
      refute changeset.valid?
      assert %{subscribed_events: ["can't be blank"]} = errors_on(changeset)
    end

    test "headers is optional" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs())
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :headers)
    end
  end

  # ---------------------------------------------------------------------------
  # URL validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — url validation" do
    test "accepts http URL" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: "http://example.com"}))
      assert changeset.valid?
    end

    test "accepts https URL" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: "https://example.com/path"}))
      assert changeset.valid?
    end

    test "rejects non-http(s) schemes" do
      for url <- ["ftp://example.com/", "file:///etc/passwd", "ws://example.com/"] do
        changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: url}))

        refute changeset.valid?, "expected #{inspect(url)} to be rejected"

        assert "must be an absolute http(s) URL with a host" in errors_on(changeset).url
      end
    end

    test "rejects relative / origin-form URLs" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: "/path"}))
      refute changeset.valid?
      assert "must be an absolute http(s) URL with a host" in errors_on(changeset).url
    end

    test "rejects URL exceeding max length" do
      long_url = "https://example.com/" <> String.duplicate("a", 2048)
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: long_url}))

      refute changeset.valid?
      assert "must be at most 2048 characters" in errors_on(changeset).url
    end

    test "accepts URL exactly at max length" do
      # 2048 byte_size — "https://" + host + path padded.
      base = "https://example.com/"
      pad = String.duplicate("a", 2048 - byte_size(base))
      url = base <> pad
      assert byte_size(url) == 2048

      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{url: url}))
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Secret length
  # ---------------------------------------------------------------------------

  describe "changeset/2 — secret length" do
    test "accepts secret at exactly min length (32 bytes)" do
      changeset =
        Webhook.changeset(%Webhook{}, valid_attrs(%{secret: String.duplicate("x", 32)}))

      assert changeset.valid?
    end

    test "accepts secret at exactly max length (256 bytes)" do
      changeset =
        Webhook.changeset(%Webhook{}, valid_attrs(%{secret: String.duplicate("x", 256)}))

      assert changeset.valid?
    end

    test "rejects secret below min length" do
      changeset =
        Webhook.changeset(%Webhook{}, valid_attrs(%{secret: String.duplicate("x", 31)}))

      refute changeset.valid?
      assert "must be at least 32 bytes" in errors_on(changeset).secret
    end

    test "rejects secret above max length" do
      changeset =
        Webhook.changeset(%Webhook{}, valid_attrs(%{secret: String.duplicate("x", 257)}))

      refute changeset.valid?
      assert "must be at most 256 bytes" in errors_on(changeset).secret
    end
  end

  # ---------------------------------------------------------------------------
  # Headers validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — headers" do
    test "accepts a small map of string => string" do
      changeset =
        Webhook.changeset(
          %Webhook{},
          valid_attrs(%{headers: %{"X-Custom" => "value", "X-Trace" => "abc"}})
        )

      assert changeset.valid?
    end

    test "rejects more than 20 entries" do
      headers = for i <- 1..21, into: %{}, do: {"X-Header-#{i}", "v"}
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{headers: headers}))

      refute changeset.valid?
      assert "must have at most 20 entries" in errors_on(changeset).headers
    end

    test "accepts exactly 20 entries" do
      headers = for i <- 1..20, into: %{}, do: {"X-Header-#{i}", "v"}
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{headers: headers}))
      assert changeset.valid?
    end

    test "rejects non-string keys or values" do
      # Atom-keyed map flagged.
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{headers: %{key: "v"}}))

      refute changeset.valid?
      assert "all keys and values must be strings" in errors_on(changeset).headers
    end

    test "rejects oversized header value" do
      changeset =
        Webhook.changeset(
          %Webhook{},
          valid_attrs(%{headers: %{"X-Big" => String.duplicate("a", 4097)}})
        )

      refute changeset.valid?

      assert "each header value must be at most 4096 characters" in errors_on(changeset).headers
    end
  end

  # ---------------------------------------------------------------------------
  # subscribed_events
  # ---------------------------------------------------------------------------

  describe "changeset/2 — subscribed_events" do
    test "accepts a known catalog event type" do
      changeset =
        Webhook.changeset(
          %Webhook{},
          valid_attrs(%{subscribed_events: ["edge.node.registered"]})
        )

      assert changeset.valid?
    end

    test "accepts multiple known catalog event types" do
      changeset =
        Webhook.changeset(
          %Webhook{},
          valid_attrs(%{
            subscribed_events: [
              "edge.node.registered",
              "edge.command_execution.completed",
              "edge.ssh_username.verified"
            ]
          })
        )

      assert changeset.valid?
    end

    test "rejects an empty list (must include at least one event type)" do
      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{subscribed_events: []}))

      refute changeset.valid?
      assert "must include at least one event type" in errors_on(changeset).subscribed_events
    end

    test "rejects more than 20 events" do
      events = for i <- 1..21, do: "edge.event.#{i}"

      changeset = Webhook.changeset(%Webhook{}, valid_attrs(%{subscribed_events: events}))

      refute changeset.valid?
      assert "cannot exceed 20 events" in errors_on(changeset).subscribed_events
    end

    test "rejects unknown event types (catches typos at API time)" do
      changeset =
        Webhook.changeset(
          %Webhook{},
          valid_attrs(%{
            subscribed_events: ["edge.node.registered", "edge.does_not_exist", "edge.also.fake"]
          })
        )

      refute changeset.valid?

      [error_msg] = errors_on(changeset).subscribed_events
      assert error_msg =~ "unknown event type(s)"
      assert error_msg =~ "edge.does_not_exist"
      assert error_msg =~ "edge.also.fake"
    end
  end
end
