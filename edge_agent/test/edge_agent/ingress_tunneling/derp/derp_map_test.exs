# edge_agent/test/edge_agent/ingress_tunneling/derp/derp_map_test.exs
defmodule EdgeAgent.IngressTunneling.Derp.DerpMapTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.IngressTunneling.Derp.DerpMap

  test "selects a deterministic shared relay order for either peer ordering" do
    map = %{
      "Regions" => %{
        "1" => %{
          "Nodes" => [
            %{"Name" => "relay-a", "HostName" => "a.example.test", "DERPPort" => 443},
            %{"Name" => "relay-b", "HostName" => "b.example.test", "DERPPort" => 443}
          ]
        },
        "2" => %{"Nodes" => [%{"Name" => "relay-c", "HostName" => "c.example.test", "DERPPort" => 443}]}
      }
    }

    first_key = :binary.copy(<<1>>, 32)
    second_key = :binary.copy(<<2>>, 32)

    relays = DerpMap.select_relays(map, first_key, second_key)

    assert relays != []
    assert relays == DerpMap.select_relays(map, second_key, first_key)
    assert Enum.all?(relays, &(&1.port == 443))
    assert Enum.all?(relays, &(&1.region_id == hd(relays).region_id))
  end

  test "returns no relays when the map or peer key is invalid" do
    assert [] = DerpMap.select_relays(%{"Regions" => %{}}, <<0::256>>, <<1::256>>)
    assert [] = DerpMap.select_relays(%{}, <<0::256>>, <<1::256>>)
    assert [] = DerpMap.select_relays(%{"Regions" => %{}}, <<0>>, <<1::256>>)
  end

  test "uses the standard DERP port when it is omitted or zero" do
    map = %{
      "Regions" => %{
        "1" => %{
          "Nodes" => [
            %{"Name" => "relay-default", "HostName" => "default.example.test"},
            %{"Name" => "relay-zero", "HostName" => "zero.example.test", "DERPPort" => 0}
          ]
        }
      }
    }

    relays = DerpMap.select_relays(map, :binary.copy(<<1>>, 32), :binary.copy(<<2>>, 32))

    assert length(relays) == 2
    assert Enum.all?(relays, &(&1.port == 443))
  end
end
