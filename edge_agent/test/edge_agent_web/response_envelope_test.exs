# edge_agent/test/edge_agent_web/response_envelope_test.exs
defmodule EdgeAgentWeb.ResponseEnvelopeTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdgeAgentWeb.ResponseEnvelope

  defp fake_conn(request_id \\ "test-uuid-1234") do
    :get
    |> conn("/")
    |> Plug.Conn.assign(:request_id, request_id)
  end

  # ---------------------------------------------------------------------------
  # success/2 — single resource and collection both pass `data` through
  # ---------------------------------------------------------------------------

  describe "success/2" do
    test "wraps a map payload in :data and adds :meta" do
      result = ResponseEnvelope.success(fake_conn(), %{id: "abc"})

      assert result.data == %{id: "abc"}
      assert is_map(result.meta)
    end

    test "passes the map through unchanged" do
      payload = %{id: "abc", name: "test", nested: %{a: 1}}

      assert ResponseEnvelope.success(fake_conn(), payload).data == payload
    end

    test "accepts a list payload (collection responses)" do
      payload = [%{id: "a"}, %{id: "b"}, %{id: "c"}]

      assert ResponseEnvelope.success(fake_conn(), payload).data == payload
    end

    test "meta carries the request_id from conn.assigns" do
      result = ResponseEnvelope.success(fake_conn("req-12345"), %{})

      assert result.meta.request_id == "req-12345"
    end

    test "meta.timestamp is a fresh ISO 8601 UTC datetime" do
      before = DateTime.utc_now()
      result = ResponseEnvelope.success(fake_conn(), %{})
      after_ = DateTime.utc_now()

      {:ok, parsed, _} = DateTime.from_iso8601(result.meta.timestamp)
      assert DateTime.compare(parsed, before) in [:gt, :eq]
      assert DateTime.compare(parsed, after_) in [:lt, :eq]
    end

    test "meta has exactly the documented keys (no leakage)" do
      result = ResponseEnvelope.success(fake_conn(), %{})

      assert result.meta |> Map.keys() |> Enum.sort() == [:request_id, :timestamp]
    end

    test "envelope has exactly :data and :meta at the top level" do
      result = ResponseEnvelope.success(fake_conn(), %{})

      assert result |> Map.keys() |> Enum.sort() == [:data, :meta]
    end
  end

  # ---------------------------------------------------------------------------
  # error/3,4 — error envelope with optional details
  # ---------------------------------------------------------------------------

  describe "error/3 — without details" do
    test "wraps {code, message} in :error and adds :meta" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "Resource not found")

      assert result.error.code == "not_found"
      assert result.error.message == "Resource not found"
      assert is_map(result.meta)
    end

    test "omits :details when none supplied (small envelope for simple errors)" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "x")

      refute Map.has_key?(result.error, :details)
    end

    test "envelope has exactly :error and :meta at the top level" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "x")

      assert result |> Map.keys() |> Enum.sort() == [:error, :meta]
    end

    test "error payload has exactly :code and :message when details omitted" do
      result = ResponseEnvelope.error(fake_conn(), "not_found", "x")

      assert result.error |> Map.keys() |> Enum.sort() == [:code, :message]
    end

    test "meta carries the request_id" do
      result = ResponseEnvelope.error(fake_conn("req-err"), "not_found", "x")

      assert result.meta.request_id == "req-err"
    end
  end

  describe "error/4 — with details" do
    test "includes :details when supplied (typically validation_failed)" do
      details = %{name: ["can't be blank"], age: ["is invalid"]}

      result =
        ResponseEnvelope.error(fake_conn(), "validation_failed", "Validation failed", details)

      assert result.error.code == "validation_failed"
      assert result.error.message == "Validation failed"
      assert result.error.details == details
    end

    test "explicit nil details collapses to the no-details envelope" do
      # Caller may pass `nil` rather than omit — same effect.
      result = ResponseEnvelope.error(fake_conn(), "not_found", "x", nil)

      refute Map.has_key?(result.error, :details)
    end

    test "empty map details are preserved (different from nil)" do
      # An empty %{} is a real value — details exist, just empty. We don't
      # collapse to nil semantics. Pin so a future "treat empty as nil"
      # change is intentional.
      result = ResponseEnvelope.error(fake_conn(), "validation_failed", "x", %{})

      assert result.error.details == %{}
    end
  end
end
