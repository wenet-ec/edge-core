# edge_admin/test/edge_admin/events/webhooks/delivery_test.exs
defmodule EdgeAdmin.Events.Webhooks.DeliveryTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Delivery
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  defp webhook(overrides \\ %{}) do
    base = %Webhook{
      id: "webhook-uuid-1",
      url: "https://example.com/hook",
      secret: "32-bytes-of-shared-secret-stuff!",
      headers: nil,
      subscribed_events: ["edge.node.registered"]
    }

    struct(base, overrides)
  end

  defp envelope, do: %{"id" => "evt-1", "type" => "edge.node.registered", "data" => %{"x" => 1}}

  # ---------------------------------------------------------------------------
  # sign/2 — HMAC-SHA256, lowercase hex, no prefix
  # ---------------------------------------------------------------------------

  describe "sign/2" do
    test "is deterministic for the same (secret, body)" do
      secret = "shared-secret"
      body = ~s({"id":"1","type":"test"})

      assert Delivery.sign(secret, body) == Delivery.sign(secret, body)
    end

    test "differs for different bodies" do
      refute Delivery.sign("secret", "body-1") == Delivery.sign("secret", "body-2")
    end

    test "differs for different secrets (the whole point of HMAC)" do
      refute Delivery.sign("secret-a", "body") == Delivery.sign("secret-b", "body")
    end

    test "produces lowercase hex (64 chars for SHA256)" do
      sig = Delivery.sign("secret", "body")

      assert String.length(sig) == 64
      assert sig == String.downcase(sig)
      assert Regex.match?(~r/\A[0-9a-f]+\z/, sig)
    end

    test "matches a known test vector" do
      # Cross-check: HMAC-SHA256 of "" keyed by "" is the empty-key digest.
      # Specific bytes pinned so a future swap of the algorithm or encoding
      # surfaces immediately.
      assert Delivery.sign("key", "The quick brown fox jumps over the lazy dog") ==
               "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
    end
  end

  # ---------------------------------------------------------------------------
  # build_headers/2
  # ---------------------------------------------------------------------------

  describe "build_headers/2" do
    test "always includes Content-Type and X-Edge-Signature" do
      headers = Delivery.build_headers(webhook(), "body")

      assert {"content-type", "application/cloudevents+json"} in headers

      sig_entry = Enum.find(headers, fn {k, _} -> k == "x-edge-signature" end)
      assert {_, "sha256=" <> hex} = sig_entry
      assert String.length(hex) == 64
    end

    test "X-Edge-Signature value matches sign/2 for the same body" do
      body = ~s({"id":"e1"})
      [{"content-type", _}, {"x-edge-signature", sig_header} | _] = Delivery.build_headers(webhook(), body)

      assert sig_header == "sha256=" <> Delivery.sign(webhook().secret, body)
    end

    test "appends operator-supplied headers as-is, after the base headers" do
      hook = webhook(%{headers: %{"X-Custom" => "value", "X-Trace" => "abc"}})
      headers = Delivery.build_headers(hook, "body")

      # Base headers come first.
      assert Enum.at(headers, 0) == {"content-type", "application/cloudevents+json"}
      assert match?({"x-edge-signature", _}, Enum.at(headers, 1))

      # Custom headers follow (order within them is map iteration, so just
      # check membership).
      assert {"X-Custom", "value"} in headers
      assert {"X-Trace", "abc"} in headers
    end

    test "treats nil headers map as empty" do
      headers = Delivery.build_headers(webhook(%{headers: nil}), "body")

      assert length(headers) == 2
      assert {"content-type", "application/cloudevents+json"} in headers
    end
  end

  # ---------------------------------------------------------------------------
  # classify/3 — retry decision matrix
  # ---------------------------------------------------------------------------

  describe "classify/3 — successes" do
    test "200 → :ok" do
      assert Delivery.classify({:ok, %Req.Response{status: 200}}, webhook(), envelope()) == :ok
    end

    test "all of 200..299 → :ok" do
      for status <- [200, 201, 202, 204, 299] do
        assert Delivery.classify({:ok, %Req.Response{status: status}}, webhook(), envelope()) ==
                 :ok
      end
    end
  end

  describe "classify/3 — recoverable HTTP statuses" do
    test "408 / 429 / 503 → recoverable" do
      for status <- [408, 429, 503] do
        assert Delivery.classify({:ok, %Req.Response{status: status}}, webhook(), envelope()) ==
                 {:recoverable, {:http_status, status}}
      end
    end
  end

  describe "classify/3 — terminal HTTP statuses" do
    test "other 4xx → terminal (receiver said no, don't retry)" do
      for status <- [400, 401, 403, 404, 410, 422] do
        assert Delivery.classify({:ok, %Req.Response{status: status}}, webhook(), envelope()) ==
                 {:terminal, {:http_status, status}}
      end
    end

    test "other 5xx → terminal" do
      # 503 is recoverable (matched above). 500/502/504 are not in the
      # recoverable list and fall through to terminal — matches the docstring.
      for status <- [500, 502, 504] do
        assert Delivery.classify({:ok, %Req.Response{status: status}}, webhook(), envelope()) ==
                 {:terminal, {:http_status, status}}
      end
    end
  end

  describe "classify/3 — network errors" do
    test "named transient errors → recoverable" do
      for reason <- [:timeout, :econnrefused, :closed, :nxdomain, :ehostunreach] do
        assert Delivery.classify({:error, %{reason: reason}}, webhook(), envelope()) ==
                 {:recoverable, {:network, reason}}
      end
    end
  end

  describe "classify/3 — unknown transport errors" do
    test "any other Req error wraps as recoverable transport error (one retry over mis-classifying)" do
      error = %RuntimeError{message: "weird thing"}

      assert Delivery.classify({:error, error}, webhook(), envelope()) ==
               {:recoverable, {:transport, error}}
    end

    test "structs without :reason fall through to the transport clause" do
      # %{} would also match the named-reason clause guard — pin the actual
      # behaviour: only the named atoms route there; everything else is
      # :transport.
      error = %{some: "shape"}

      assert Delivery.classify({:error, error}, webhook(), envelope()) ==
               {:recoverable, {:transport, error}}
    end
  end
end
