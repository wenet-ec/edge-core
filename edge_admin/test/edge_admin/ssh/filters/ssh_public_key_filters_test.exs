# edge_admin/test/edge_admin/ssh/filters/ssh_public_key_filters_test.exs
defmodule EdgeAdmin.Ssh.Filters.SshPublicKeyFiltersTest do
  use EdgeAdmin.DataCase, async: false

  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.Filters.SshPublicKeyFilters
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  defp insert_cluster(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          name: "cluster-#{:rand.uniform(999_999)}",
          ipv4_range: "100.64.#{:rand.uniform(200)}.0/24"
        },
        overrides
      )

    Repo.insert!(struct(Cluster, attrs))
  end

  defp insert_node(cluster_id) do
    Repo.insert!(
      struct(Node, %{
        id: Ecto.UUID.generate(),
        cluster_id: cluster_id,
        id_type: "persistent",
        status: "healthy",
        version: "0.1.0",
        http_port: 44_000,
        ssh_port: 40_022,
        host_metrics_port: 9100,
        wireguard_metrics_port: 9586,
        http_proxy_port: 8080,
        socks5_proxy_port: 1080,
        api_token: Ecto.UUID.generate(),
        proxy_password: Ecto.UUID.generate()
      })
    )
  end

  defp insert_ssh_username(node_id, opts \\ []) do
    username = Keyword.get(opts, :username, "user-#{:rand.uniform(999_999)}")

    Repo.insert!(
      struct(SshUsername, %{
        id: Ecto.UUID.generate(),
        node_id: node_id,
        username: username
      })
    )
  end

  defp insert_public_key(ssh_username_id, opts \\ []) do
    key_name = Keyword.get(opts, :key_name, "key-#{:rand.uniform(999_999)}")
    public_key = Keyword.get(opts, :public_key, "ssh-ed25519 AAAA#{Ecto.UUID.generate()} comment")

    Repo.insert!(
      struct(SshPublicKey, %{
        id: Ecto.UUID.generate(),
        ssh_username_id: ssh_username_id,
        key_name: key_name,
        public_key: public_key
      })
    )
  end

  defp base_query do
    from(k in SshPublicKey,
      join: u in assoc(k, :ssh_username),
      join: n in assoc(u, :node),
      join: c in assoc(n, :cluster),
      select: k
    )
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # apply_node_id/2 — filters via the node binding (n.id)
  # ---------------------------------------------------------------------------

  describe "apply_node_id/2" do
    test "matches keys whose username's node has the given id" do
      cluster = insert_cluster()
      node_a = insert_node(cluster.id)
      node_b = insert_node(cluster.id)

      user_a = insert_ssh_username(node_a.id)
      user_b = insert_ssh_username(node_b.id)

      key_a = insert_public_key(user_a.id)
      _key_b = insert_public_key(user_b.id)

      query = SshPublicKeyFilters.apply_node_id(base_query(), [%{op: :==, value: node_a.id}])

      assert ids(query) == [key_a.id]
    end

    test "empty filters list → query unchanged (early return clause)" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)
      b = insert_public_key(user.id)

      assert ids(SshPublicKeyFilters.apply_node_id(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)

      query = SshPublicKeyFilters.apply_node_id(base_query(), [%{op: :ilike, value: "anything"}])
      assert ids(query) == [a.id]
    end

    test "non-binary value → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)

      query = SshPublicKeyFilters.apply_node_id(base_query(), [%{op: :==, value: 12_345}])
      assert ids(query) == [a.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_username/2 — filters via the username binding (u.username)
  # ---------------------------------------------------------------------------

  describe "apply_username/2" do
    test "== matches by exact username" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      alice = insert_ssh_username(node.id, username: "alice")
      bob = insert_ssh_username(node.id, username: "bob")

      key_alice = insert_public_key(alice.id)
      _key_bob = insert_public_key(bob.id)

      query = SshPublicKeyFilters.apply_username(base_query(), [%{op: :==, value: "alice"}])

      assert ids(query) == [key_alice.id]
    end

    test "ilike matches case-insensitively" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      alice = insert_ssh_username(node.id, username: "alice")
      _bob = insert_ssh_username(node.id, username: "bob")

      key_alice = insert_public_key(alice.id)

      query =
        SshPublicKeyFilters.apply_username(base_query(), [%{op: :ilike, value: "ALI%"}])

      assert ids(query) == [key_alice.id]
    end

    test "empty filters list → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)
      b = insert_public_key(user.id)

      assert ids(SshPublicKeyFilters.apply_username(base_query(), [])) == Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)

      query = SshPublicKeyFilters.apply_username(base_query(), [%{op: :>=, value: 5}])
      assert ids(query) == [a.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_cluster_name/2 — filters via the cluster binding (c.name, 4th binding)
  # ---------------------------------------------------------------------------

  describe "apply_cluster_name/2" do
    test "== matches by exact cluster name" do
      cluster_alpha = insert_cluster(%{name: "alpha"})
      cluster_bravo = insert_cluster(%{name: "bravo"})

      node_alpha = insert_node(cluster_alpha.id)
      node_bravo = insert_node(cluster_bravo.id)

      user_alpha = insert_ssh_username(node_alpha.id)
      user_bravo = insert_ssh_username(node_bravo.id)

      key_alpha = insert_public_key(user_alpha.id)
      _key_bravo = insert_public_key(user_bravo.id)

      query =
        SshPublicKeyFilters.apply_cluster_name(base_query(), [%{op: :==, value: "alpha"}])

      assert ids(query) == [key_alpha.id]
    end

    test "ilike matches case-insensitively" do
      cluster_prod = insert_cluster(%{name: "prod-east"})
      cluster_staging = insert_cluster(%{name: "staging-east"})

      node_prod = insert_node(cluster_prod.id)
      node_staging = insert_node(cluster_staging.id)

      user_prod = insert_ssh_username(node_prod.id)
      user_staging = insert_ssh_username(node_staging.id)

      key_prod = insert_public_key(user_prod.id)
      _key_staging = insert_public_key(user_staging.id)

      query =
        SshPublicKeyFilters.apply_cluster_name(base_query(), [%{op: :ilike, value: "PROD%"}])

      assert ids(query) == [key_prod.id]
    end

    test "empty filters list → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)
      b = insert_public_key(user.id)

      assert ids(SshPublicKeyFilters.apply_cluster_name(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)
      a = insert_public_key(user.id)

      query = SshPublicKeyFilters.apply_cluster_name(base_query(), [%{op: :>=, value: 5}])
      assert ids(query) == [a.id]
    end
  end
end
