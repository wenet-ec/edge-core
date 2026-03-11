# Nexmaker

Elixir wrapper for [Netmaker](https://github.com/gravitl/netmaker) — the WireGuard mesh VPN used by Edge Core. Provides two interfaces: an HTTP client for the Netmaker REST API, and a thin wrapper around the `netclient` CLI for VPN lifecycle operations.

Used as a shared path dependency by both `edge_admin` and `edge_agent`. Neither application calls Netmaker or netclient directly.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:nexmaker, path: "../nexmaker"}
  ]
end
```

## Configuration

```elixir
# config/runtime.exs
config :nexmaker,
  base_url: System.get_env("NETMAKER_API_URL", "http://netmaker:8081"),
  master_key: System.get_env("NETMAKER_MASTER_KEY")
```

## Usage

### Netmaker REST API (`Nexmaker.Api.*`)

```elixir
# Create a VPN network for an edge cluster
{:ok, network} = Nexmaker.Api.Networks.create("cluster-abc", addressrange: "100.64.0.0/24")

# Create a single-use enrollment key for agent bootstrapping
{:ok, key} = Nexmaker.Api.EnrollmentKeys.create("cluster-abc", uses_remaining: 1)

# Delete a node from a network
:ok = Nexmaker.Api.Nodes.delete("cluster-abc", node_id)
```

Available modules: `Networks`, `EnrollmentKeys`, `Hosts`, `Nodes`, `DNS`, `Superadmin`, `Gateways.Ingress`, `Gateways.Egress`, `Gateways.Relay`, `AdvancedEgress`, `InternetGateway`, `ExternalClients`, `EMQX`.

### netclient CLI (`Nexmaker.Cli`)

```elixir
# Join a VPN network using an enrollment token
{:ok, _} = Nexmaker.Cli.join_network(token: key["token"])

# Check VPN health (network membership + peer reachability)
{:ok, :healthy, info} = Nexmaker.Cli.health_check()

# List all networks this host is joined to
{:ok, networks} = Nexmaker.Cli.list_networks()

# Leave a network
:ok = Nexmaker.Cli.leave_network("cluster-old-id")
```

Requires the `netclient` binary to be present in the container (bundled in the Edge Agent image).
