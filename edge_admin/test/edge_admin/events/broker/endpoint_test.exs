# edge_admin/test/edge_admin/events/broker/endpoint_test.exs
defmodule EdgeAdmin.Events.Broker.EndpointTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Events.Broker.Endpoint

  describe "parse_list/2" do
    test "parses hostnames and bracketed IPv6 endpoints" do
      assert {:ok, [{"broker-a", 1883}, {"::1", 1884}]} =
               Endpoint.parse_list("broker-a:1883, [::1]:1884", 1883)
    end

    test "accepts an optional URI scheme and default port" do
      assert {:ok, [{"broker-a", 1883}]} = Endpoint.parse_list("mqtt://broker-a", 1883)
    end

    test "rejects empty and malformed endpoints" do
      assert {:error, _} = Endpoint.parse_list("", 1883)
      assert {:error, _} = Endpoint.parse_list("broker-a:not-a-port", 1883)
      assert {:error, _} = Endpoint.parse_list("broker-a:70000", 1883)
    end
  end
end
