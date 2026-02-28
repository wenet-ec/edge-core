# nexmaker/lib/nexmaker.ex
defmodule Nexmaker do
  @moduledoc """
  Elixir library for interacting with Netmaker infrastructure.

  Nexmaker provides two main interfaces:

  1. **Nexmaker.Cli** - Thin wrapper around netclient CLI for VPN operations
  2. **Nexmaker.Api** - HTTP client for Netmaker REST API

  ## Installation

  Add `nexmaker` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:nexmaker, path: "../nexmaker"}
        ]
      end

  ## Configuration

  Configure Nexmaker in your `config/runtime.exs`:

      config :nexmaker,
        base_url: System.get_env("NETMAKER_URL", "http://netmaker:8081"),
        master_key: System.get_env("NETMAKER_MASTER_KEY")

  ## CLI Usage (VPN Operations)

  Use `Nexmaker.Cli` for VPN lifecycle operations:

      # Join a network
      {:ok, _} = Nexmaker.Cli.join_network(enrollment_key)

      # Check connection status
      {:ok, info} = Nexmaker.Cli.check_connection("admin-cluster")

      # List all networks
      {:ok, networks} = Nexmaker.Cli.list_networks()

      # Leave a network
      :ok = Nexmaker.Cli.leave_network("old-cluster")

  ## API Usage (Infrastructure Management)

  Use `Nexmaker.Api.*` modules for Netmaker API operations:

      # Create a network
      {:ok, network} = Nexmaker.Api.Networks.create("cluster-abc",
        addressrange: "100.64.0.0/24"
      )

      # Create enrollment key
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("cluster-abc",
        uses_remaining: 1,
        expiration: 3600
      )

      # Create custom DNS entry
      {:ok, _} = Nexmaker.Api.DNS.create("cluster-abc", %{
        name: "gateway.cluster-abc.nm.internal",
        address: "10.71.128.1"
      })

  ## Available Modules

  ### CLI Module
  - `Nexmaker.Cli` - netclient wrapper for VPN operations

  ### API Modules
  - `Nexmaker.Api` - Base HTTP client
  - `Nexmaker.Api.Networks` - Network management (6 endpoints)
  - `Nexmaker.Api.EnrollmentKeys` - Enrollment key management (4 endpoints)
  - `Nexmaker.Api.Hosts` - Host management (11 endpoints)
  - `Nexmaker.Api.Nodes` - Node management (6 endpoints)
  - `Nexmaker.Api.DNS` - DNS management (8 endpoints)
  - `Nexmaker.Api.Superadmin` - Superadmin bootstrap (3 endpoints)

  ## Architecture Notes

  - **Host vs Node**: Host = Physical machine, Node = Network membership
  - **Authentication**: All API calls use MASTER_KEY via Bearer token
  - **Netclient daemon**: Handles auto-reconnection, runs as background service
  - **DNS pattern**: `{hostname}.{network}.nm.internal`

  For detailed documentation, see individual module docs.
  """
end
