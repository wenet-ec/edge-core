# edge_admin/test/support/fixtures.ex
defmodule EdgeAdmin.Test.Fixtures do
  @moduledoc "Shared database fixtures for Admin tests."

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Repo
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @ipv4_test_subnet_count 16_384
  @ipv6_test_subnet_count 65_536
  @fixture_timestamp ~U[2026-01-01 00:00:00Z]

  @spec insert_cluster!() :: Cluster.t()
  @spec insert_cluster!(map()) :: Cluster.t()
  def insert_cluster!(attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: unique_cluster_name(),
      ipv4_range: unique_ipv4_range(),
      ipv6_range: unique_ipv6_range()
    }

    Repo.insert!(struct(Cluster, Map.merge(defaults, attrs)))
  end

  @spec insert_node!(String.t()) :: Node.t()
  @spec insert_node!(String.t(), map()) :: Node.t()
  def insert_node!(cluster_id, attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      cluster_id: cluster_id,
      vpn_host_id: Ecto.UUID.generate(),
      status: :healthy,
      version: "0.1.0",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9586,
      http_proxy_port: 8080,
      socks5_proxy_port: 1080,
      api_token: Ecto.UUID.generate(),
      proxy_password: Ecto.UUID.generate(),
      ingress_public_key: unique_ingress_public_key()
    }

    Repo.insert!(struct(Node, Map.merge(defaults, attrs)))
  end

  @spec insert_enrollment_key!(String.t()) :: EnrollmentKey.t()
  @spec insert_enrollment_key!(String.t(), map()) :: EnrollmentKey.t()
  def insert_enrollment_key!(cluster_id, attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      cluster_id: cluster_id,
      name: unique_name("key"),
      key: "blob-#{Ecto.UUID.generate()}",
      uses_remaining: 1,
      expires_at: nil,
      last_used_at: nil
    }

    # Preserve explicit nil overrides such as unlimited-use keys.
    %EnrollmentKey{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @spec insert_command!() :: Command.t()
  @spec insert_command!(map()) :: Command.t()
  def insert_command!(attrs \\ %{}) do
    defaults = %{id: Ecto.UUID.generate(), command_text: "echo hello", targeting: %{}}
    Repo.insert!(struct(Command, Map.merge(defaults, attrs)))
  end

  @spec insert_command_execution!(map()) :: CommandExecution.t()
  def insert_command_execution!(attrs) do
    defaults = %{id: Ecto.UUID.generate(), status: :pending}

    %CommandExecution{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @spec insert_ssh_username!(String.t()) :: SshUsername.t()
  @spec insert_ssh_username!(String.t(), map()) :: SshUsername.t()
  def insert_ssh_username!(node_id, attrs \\ %{}) do
    defaults = %{id: Ecto.UUID.generate(), node_id: node_id, username: unique_name("user")}
    Repo.insert!(struct(SshUsername, Map.merge(defaults, attrs)))
  end

  @spec insert_ssh_public_key!(String.t()) :: SshPublicKey.t()
  @spec insert_ssh_public_key!(String.t(), map()) :: SshPublicKey.t()
  def insert_ssh_public_key!(ssh_username_id, attrs \\ %{}) do
    suffix = unique_name("key")

    defaults = %{
      id: Ecto.UUID.generate(),
      ssh_username_id: ssh_username_id,
      key_name: suffix,
      public_key: "ssh-ed25519 AAAA#{suffix} test@example.com"
    }

    Repo.insert!(struct(SshPublicKey, Map.merge(defaults, attrs)))
  end

  @spec insert_alias!(String.t(), String.t()) :: Alias.t()
  @spec insert_alias!(String.t(), String.t(), map()) :: Alias.t()
  def insert_alias!(node_id, cluster_id, attrs \\ %{}) do
    defaults = %{
      id: Ecto.UUID.generate(),
      name: unique_name("alias"),
      node_id: node_id,
      cluster_id: cluster_id
    }

    Repo.insert!(struct(Alias, Map.merge(defaults, attrs)))
  end

  @spec insert_node_diagnostic!(String.t()) :: NodeDiagnostic.t()
  @spec insert_node_diagnostic!(String.t(), map()) :: NodeDiagnostic.t()
  def insert_node_diagnostic!(node_id, attrs \\ %{}) do
    defaults = %{
      node_id: node_id,
      report: %{"overall" => "pass"},
      inserted_at: @fixture_timestamp,
      updated_at: @fixture_timestamp
    }

    Repo.insert!(struct(NodeDiagnostic, Map.merge(defaults, attrs)))
  end

  @spec insert_self_update_request!(map()) :: SelfUpdateRequest.t()
  def insert_self_update_request!(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      targeting: %{"type" => "all"},
      status: :pending,
      summary: nil,
      inserted_at: @fixture_timestamp,
      updated_at: @fixture_timestamp
    }

    Repo.insert!(struct(SelfUpdateRequest, Map.merge(defaults, attrs)))
  end

  @spec insert_webhook!(map()) :: Webhook.t()
  def insert_webhook!(attrs) do
    defaults = %{
      url: "https://203.0.113.10/#{unique_name("webhook")}",
      secret: String.duplicate("x", 32),
      subscribed_events: ["edge.node.registered"],
      inserted_at: @fixture_timestamp,
      updated_at: @fixture_timestamp
    }

    %Webhook{}
    |> Webhook.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @doc "Returns distinct canonical WireGuard key material for node fixtures."
  @spec unique_ingress_public_key() :: String.t()
  def unique_ingress_public_key do
    key_id = unique_id()
    Base.encode64(<<key_id::unsigned-big-integer-size(64), 0::size(192)>>)
  end

  @doc "Returns a cluster name unique within the current test VM."
  @spec unique_cluster_name() :: String.t()
  def unique_cluster_name do
    "cluster-#{Integer.to_string(unique_id(), 36)}"
  end

  @doc "Returns a prefixed identifier unique within the current test VM."
  @spec unique_name(String.t()) :: String.t()
  def unique_name(prefix) when is_binary(prefix) do
    "#{prefix}-#{Integer.to_string(unique_id(), 36)}"
  end

  @doc "Returns a distinct CGNAT /24 for each cluster fixture."
  @spec unique_ipv4_range() :: String.t()
  def unique_ipv4_range do
    index = rem(unique_id(), @ipv4_test_subnet_count)

    second_octet = 64 + div(index, 256)
    third_octet = rem(index, 256)
    "100.#{second_octet}.#{third_octet}.0/24"
  end

  @doc "Returns a distinct ULA /64 for each cluster fixture."
  @spec unique_ipv6_range() :: String.t()
  def unique_ipv6_range do
    index = rem(unique_id(), @ipv6_test_subnet_count)

    "fd7a:91c2:4e8b:#{Integer.to_string(index, 16)}::/64"
  end

  defp unique_id, do: :erlang.unique_integer([:positive, :monotonic])
end
