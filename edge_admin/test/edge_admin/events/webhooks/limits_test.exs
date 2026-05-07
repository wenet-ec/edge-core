# edge_admin/test/edge_admin/events/webhooks/limits_test.exs
defmodule EdgeAdmin.Events.Webhooks.LimitsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Webhooks.Limits

  # The whole point of this module is that REST OpenApiSpex, MCP Peri schemas,
  # the Form, and the Schema all reference these constants. If a constant moves,
  # the change should be visible — pin them so tightening a limit is an
  # intentional act, not a silent shift.

  describe "limit constants" do
    test "max_url_length is 2048" do
      assert Limits.max_url_length() == 2048
    end

    test "min_secret_bytes is 32" do
      assert Limits.min_secret_bytes() == 32
    end

    test "max_secret_bytes is 256" do
      assert Limits.max_secret_bytes() == 256
    end

    test "max_headers is 20" do
      assert Limits.max_headers() == 20
    end

    test "max_header_value_length is 4096" do
      assert Limits.max_header_value_length() == 4096
    end

    test "min_subscribed_events is 1" do
      assert Limits.min_subscribed_events() == 1
    end

    test "max_subscribed_events is 20" do
      assert Limits.max_subscribed_events() == 20
    end

    test "max_event_type_length is 256" do
      assert Limits.max_event_type_length() == 256
    end
  end

  describe "limit invariants" do
    test "min_secret_bytes <= max_secret_bytes" do
      assert Limits.min_secret_bytes() <= Limits.max_secret_bytes()
    end

    test "min_subscribed_events <= max_subscribed_events" do
      assert Limits.min_subscribed_events() <= Limits.max_subscribed_events()
    end

    test "all limits are positive integers" do
      for fun <- [
            :max_url_length,
            :min_secret_bytes,
            :max_secret_bytes,
            :max_headers,
            :max_header_value_length,
            :min_subscribed_events,
            :max_subscribed_events,
            :max_event_type_length
          ] do
        value = apply(Limits, fun, [])
        assert is_integer(value), "#{fun} should be an integer"
        assert value > 0, "#{fun} should be positive"
      end
    end
  end
end
