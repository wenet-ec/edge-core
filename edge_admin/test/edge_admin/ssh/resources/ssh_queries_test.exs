# edge_admin/test/edge_admin/ssh/resources/ssh_queries_test.exs
defmodule EdgeAdmin.Ssh.Resources.SshQueriesTest do
  use EdgeAdmin.DataCase, async: false

  alias EdgeAdmin.Ssh.Resources.SshPublicKeyResources
  alias EdgeAdmin.Ssh.Resources.SshUsernameResources
  alias EdgeAdmin.Test.Fixtures

  defp insert_cluster(overrides \\ %{}), do: Fixtures.insert_cluster!(overrides)
  defp insert_node(cluster_id), do: Fixtures.insert_node!(cluster_id)

  defp insert_ssh_username(node_id, opts \\ []), do: Fixtures.insert_ssh_username!(node_id, Map.new(opts))

  defp insert_public_key(ssh_username_id, opts \\ []),
    do: Fixtures.insert_ssh_public_key!(ssh_username_id, Map.new(opts))

  defp ids(records), do: records |> Enum.map(& &1.id) |> Enum.sort()

  describe "list_ssh_usernames/1 merged filters" do
    test "cluster_name__in accepts comma-separated exact IN values" do
      alpha = insert_cluster(%{name: "alpha"})
      bravo = insert_cluster(%{name: "bravo"})
      charlie = insert_cluster(%{name: "charlie"})

      user_alpha = alpha.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      user_bravo = bravo.id |> insert_node() |> then(&insert_ssh_username(&1.id))
      charlie.id |> insert_node() |> then(&insert_ssh_username(&1.id))

      assert {:ok, {users, _meta}} = SshUsernameResources.list(%{"cluster_name__in" => "alpha,bravo"})
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

      assert {:ok, {users, _meta}} = SshUsernameResources.list(%{"key_name__in" => "laptop,server"})
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

      assert {:ok, {keys, _meta}} = SshPublicKeyResources.list(%{"username__in" => "alice,bob"})
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

      assert {:ok, {keys, _meta}} = SshPublicKeyResources.list(%{"cluster_name__in" => "alpha,bravo"})
      assert ids(keys) == ids([alpha_key, bravo_key])
    end

    test "key_name__in accepts comma-separated exact IN values" do
      cluster = insert_cluster()
      node = insert_node(cluster.id)
      user = insert_ssh_username(node.id)

      laptop = insert_public_key(user.id, key_name: "laptop")
      server = insert_public_key(user.id, key_name: "server")
      insert_public_key(user.id, key_name: "tablet")

      assert {:ok, {keys, _meta}} = SshPublicKeyResources.list(%{"key_name__in" => "laptop,server"})
      assert ids(keys) == ids([laptop, server])
    end
  end
end
