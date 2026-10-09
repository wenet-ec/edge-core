# edge_agent/test/edge_agent/ingress_tunneling/configuration_test.exs
defmodule EdgeAgent.IngressTunneling.ConfigurationTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.IngressTunneling.Configuration

  test "accepts a complete snapshot with one dual-stack peer" do
    assert {:ok, config} = Configuration.validate(valid_config())
    assert length(config["peers"]) == 1
  end

  test "rejects peer routes beyond that peer's tunnel addresses" do
    config = valid_config()
    peer = config["peers"] |> hd() |> Map.put("allowed_ips", ["0.0.0.0/0", "fd20:240::2/128"])
    config = Map.put(config, "peers", [peer])

    assert {:error, :invalid_ingress_tunneling_configuration} = Configuration.validate(config)
  end

  test "rejects duplicate Tunnel addresses assigned to different peers" do
    peer = hd(valid_config()["peers"])
    duplicate = Map.put(peer, "tunnel_public_key", key(3))
    config = Map.put(valid_config(), "peers", [peer, duplicate])

    assert {:error, :invalid_ingress_tunneling_configuration} = Configuration.validate(config)
  end

  test "rejects a peer address that collides with an Ingress address" do
    config = valid_config()
    [peer] = config["peers"]
    peer = Map.put(peer, "tunnel_ipv4_address", "10.240.0.1/32")
    peer = Map.put(peer, "allowed_ips", ["10.240.0.1/32", "fd20:240::2/128"])

    assert {:error, :invalid_ingress_tunneling_configuration} =
             Configuration.validate(Map.put(config, "peers", [peer]))
  end

  test "rejects the Ingress identity as a Tunnel peer" do
    config = valid_config()
    [peer] = config["peers"]
    peer = Map.put(peer, "tunnel_public_key", config["ingress_public_key"])

    assert {:error, :invalid_ingress_tunneling_configuration} =
             Configuration.validate(Map.put(config, "peers", [peer]))
  end

  defp valid_config do
    %{
      "ingress_public_key" => key(1),
      "ingress_ipv4_addresses" => ["10.240.0.1/32"],
      "ingress_ipv6_addresses" => ["fd20:240::1/128"],
      "vpn_dns_suffix" => "cluster-1.nm.internal",
      "vpn_ipv4_range" => "100.64.0.0/24",
      "vpn_ipv6_range" => "fd7a:91c2:4e8c:1::/64",
      "core_derp_map_urls" => ["https://relay.example.test/map"],
      "core_stun_servers" => ["stun.example.test:3478"],
      "peers" => [
        %{
          "tunnel_public_key" => key(2),
          "tunnel_ipv4_address" => "10.240.0.2/32",
          "tunnel_ipv6_address" => "fd20:240::2/128",
          "allowed_ips" => ["10.240.0.2/32", "fd20:240::2/128"]
        }
      ]
    }
  end

  defp key(byte), do: <<byte>> |> :binary.copy(32) |> Base.encode64()
end
