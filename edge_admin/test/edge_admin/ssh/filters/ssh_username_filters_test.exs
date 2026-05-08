# edge_admin/test/edge_admin/ssh/filters/ssh_username_filters_test.exs
defmodule EdgeAdmin.Ssh.Filters.SshUsernameFiltersTest do
  use EdgeAdmin.DataCase, async: false

  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.Filters.SshUsernameFilters
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
        status: :healthy,
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
    password_hash = Keyword.get(opts, :password_hash, nil)
    username = Keyword.get(opts, :username, "user-#{:rand.uniform(999_999)}")

    %SshUsername{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      node_id: node_id,
      username: username,
      password_hash: password_hash
    })
    |> Repo.insert!()
  end

  defp base_query do
    from(u in SshUsername,
      join: n in assoc(u, :node),
      join: c in assoc(n, :cluster),
      select: u
    )
  end

  defp ids(query), do: query |> Repo.all() |> Enum.map(& &1.id) |> Enum.sort()

  # ---------------------------------------------------------------------------
  # apply_has_password/2 — virtual boolean: password_hash IS [NOT] NULL
  # ---------------------------------------------------------------------------

  describe "apply_has_password/2" do
    test "true matches usernames with non-null password_hash" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      with_password = insert_ssh_username(node.id, password_hash: "$argon2id$abc")
      _without = insert_ssh_username(node.id, password_hash: nil)

      query = SshUsernameFilters.apply_has_password(SshUsername, [%{op: :==, value: true}])

      assert ids(query) == [with_password.id]
    end

    test "false matches usernames with null password_hash" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      _with_password = insert_ssh_username(node.id, password_hash: "$argon2id$abc")
      without = insert_ssh_username(node.id, password_hash: nil)

      query = SshUsernameFilters.apply_has_password(SshUsername, [%{op: :==, value: false}])

      assert ids(query) == [without.id]
    end

    test "string 'true' / 'false' work the same way" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      with_pw = insert_ssh_username(node.id, password_hash: "h")
      without = insert_ssh_username(node.id, password_hash: nil)

      assert ids(SshUsernameFilters.apply_has_password(SshUsername, [%{op: :==, value: "true"}])) ==
               [with_pw.id]

      assert ids(SshUsernameFilters.apply_has_password(SshUsername, [%{op: :==, value: "false"}])) ==
               [without.id]
    end

    test "no filters → query unchanged" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      a = insert_ssh_username(node.id)
      b = insert_ssh_username(node.id)

      assert ids(SshUsernameFilters.apply_has_password(SshUsername, [])) ==
               Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op → query unchanged (catch-all)" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      a = insert_ssh_username(node.id)

      query = SshUsernameFilters.apply_has_password(SshUsername, [%{op: :>, value: 5}])

      assert ids(query) == [a.id]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_cluster_name/2 — filters by node's cluster name (3rd binding)
  # ---------------------------------------------------------------------------

  describe "apply_cluster_name/2" do
    test "== matches by exact cluster name" do
      cluster_a = insert_cluster(%{name: "alpha"})
      cluster_b = insert_cluster(%{name: "bravo"})

      node_a = insert_node(cluster_a.id)
      node_b = insert_node(cluster_b.id)

      user_a = insert_ssh_username(node_a.id)
      _user_b = insert_ssh_username(node_b.id)

      query = SshUsernameFilters.apply_cluster_name(base_query(), [%{op: :==, value: "alpha"}])

      assert ids(query) == [user_a.id]
    end

    test "ilike matches by case-insensitive wildcard" do
      cluster_prod = insert_cluster(%{name: "prod-east"})
      cluster_staging = insert_cluster(%{name: "staging-east"})

      node_prod = insert_node(cluster_prod.id)
      node_staging = insert_node(cluster_staging.id)

      user_prod = insert_ssh_username(node_prod.id)
      _user_staging = insert_ssh_username(node_staging.id)

      query =
        SshUsernameFilters.apply_cluster_name(base_query(), [
          %{field: :cluster_name, op: :ilike, value: "PROD%"}
        ])

      assert ids(query) == [user_prod.id]
    end

    test "no filters → query unchanged" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      a = insert_ssh_username(node_a.id)
      b = insert_ssh_username(node_a.id)

      assert ids(SshUsernameFilters.apply_cluster_name(base_query(), [])) ==
               Enum.sort([a.id, b.id])
    end

    test "unrecognised filter op → query unchanged (catch-all)" do
      cluster_a = insert_cluster()
      node_a = insert_node(cluster_a.id)
      a = insert_ssh_username(node_a.id)

      query = SshUsernameFilters.apply_cluster_name(base_query(), [%{op: :>=, value: 5}])
      assert ids(query) == [a.id]
    end
  end
end
