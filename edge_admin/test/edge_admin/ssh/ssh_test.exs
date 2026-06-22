# edge_admin/test/edge_admin/ssh/ssh_test.exs
defmodule EdgeAdmin.SshTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh
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
        id_type: :persistent,
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
    username = Keyword.get(opts, :username, "user-#{:rand.uniform(999_999)}")

    %SshUsername{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      node_id: node_id,
      username: username
    })
    |> Repo.insert!()
  end

  defp insert_public_key(ssh_username_id, opts \\ []) do
    key_name = Keyword.get(opts, :key_name, "key-#{:rand.uniform(999_999)}")

    %SshPublicKey{}
    |> Ecto.Changeset.change(%{
      id: Ecto.UUID.generate(),
      ssh_username_id: ssh_username_id,
      key_name: key_name,
      public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForFilterTestOnly user@example.com"
    })
    |> Repo.insert!()
  end

  defp ids(records), do: records |> Enum.map(& &1.id) |> Enum.sort()

  describe "list_ssh_usernames/1 merged filters" do
    test "cluster_name__in accepts comma-separated exact IN values" do
      alpha = insert_cluster(%{name: "alpha"})
      bravo = insert_cluster(%{name: "bravo"})
      charlie = insert_cluster(%{name: "charlie"})

      user_alpha = alpha.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      user_bravo = bravo.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      charlie.id |> insert_node() |> then(&insert_ssh_username(&1.id))

      assert {:ok, {users, _meta}} = Ssh.list_ssh_usernames(%{"cluster_name__in" => "alpha,bravo"})
      assert ids(users) == ids([user_alpha, user_bravo])
    end

    test "key_name__in accepts comma-separated exact IN values" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      laptop_user = insert_ssh_username(node.id)
      server_user = insert_ssh_username(node.id)
      tablet_user = insert_ssh_username(node.id)

      insert_public_key(laptop_user.id, key_name: "laptop")
      insert_public_key(server_user.id, key_name: "server")
      insert_public_key(tablet_user.id, key_name: "tablet")

      assert {:ok, {users, _meta}} = Ssh.list_ssh_usernames(%{"key_name__in" => "laptop,server"})
      assert ids(users) == ids([laptop_user, server_user])
    end
  end

  describe "list_ssh_public_keys/1 merged filters" do
    test "username__in accepts comma-separated exact IN values" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)

      alice = insert_ssh_username(node.id, username: "alice")
      bob = insert_ssh_username(node.id, username: "bob")
      carol = insert_ssh_username(node.id, username: "carol")

      alice_key = insert_public_key(alice.id)
      bob_key = insert_public_key(bob.id)
      insert_public_key(carol.id)

      assert {:ok, {keys, _meta}} = Ssh.list_ssh_public_keys(%{"username__in" => "alice,bob"})
      assert ids(keys) == ids([alice_key, bob_key])
    end

    test "cluster_name__in accepts comma-separated exact IN values" do
      alpha = insert_cluster(%{name: "alpha"})
      bravo = insert_cluster(%{name: "bravo"})
      charlie = insert_cluster(%{name: "charlie"})

      alpha_user = alpha.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      bravo_user = bravo.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      charlie_user = charlie.id |> insert_node() |> then(&insert_ssh_username(&1.id))

      alpha_key = insert_public_key(alpha_user.id)
      bravo_key = insert_public_key(bravo_user.id)
      insert_public_key(charlie_user.id)

      assert {:ok, {keys, _meta}} = Ssh.list_ssh_public_keys(%{"cluster_name__in" => "alpha,bravo"})
      assert ids(keys) == ids([alpha_key, bravo_key])
    end

    test "key_name__in accepts comma-separated exact IN values" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)

      laptop = insert_public_key(user.id, key_name: "laptop")
      server = insert_public_key(user.id, key_name: "server")
      insert_public_key(user.id, key_name: "tablet")

      assert {:ok, {keys, _meta}} = Ssh.list_ssh_public_keys(%{"key_name__in" => "laptop,server"})
      assert ids(keys) == ids([laptop, server])
    end
  end
end
