# edge_admin/test/edge_admin/ssh/views/ssh_username_view_test.exs
defmodule EdgeAdmin.Ssh.Views.SshUsernameViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdmin.Ssh.Views.SshUsernameView

  defp public_key(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %SshPublicKey{
      id: "key-uuid",
      public_key: "ssh-ed25519 AAAA user@host",
      key_name: "laptop",
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  defp username_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %SshUsername{
      id: "username-uuid-1",
      username: "alice",
      password_hash: nil,
      node_id: "node-uuid-1",
      ssh_public_keys: [],
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      user = username_fixture()

      result = SshUsernameView.render(user)

      assert result.id == user.id
      assert result.username == "alice"
      assert result.has_password == false
      assert result.node_id == "node-uuid-1"
      assert result.public_keys == []
      assert result.inserted_at == user.inserted_at
      assert result.updated_at == user.updated_at
    end

    test "has_password is true when password_hash is set" do
      user = username_fixture(%{password_hash: "$argon2id$..."})

      assert SshUsernameView.render(user).has_password == true
    end

    test "has_password is false when password_hash is nil" do
      user = username_fixture(%{password_hash: nil})

      assert SshUsernameView.render(user).has_password == false
    end

    test "SECURITY: password_hash is NEVER in the rendered output" do
      # Critical contract — REST and MCP must not leak the Argon2 hash. The
      # view enforces this by simply not including the field. Drift here is
      # a security regression, so pin it explicitly.
      user = username_fixture(%{password_hash: "$argon2id$leaked-hash-value"})

      result = SshUsernameView.render(user)

      refute Map.has_key?(result, :password_hash)
      refute result |> inspect() |> String.contains?("leaked-hash-value")
    end

    test "renders public_keys as nested summaries" do
      key1 = public_key(%{id: "k1", key_name: "laptop", public_key: "ssh-ed25519 AAAA u@h"})
      key2 = public_key(%{id: "k2", key_name: "desktop", public_key: "ssh-rsa BBBB u@h"})

      user = username_fixture(%{ssh_public_keys: [key1, key2]})

      result = SshUsernameView.render(user)

      assert length(result.public_keys) == 2

      [first, second] = result.public_keys

      assert first.id == "k1"
      assert first.key_name == "laptop"
      assert first.public_key == "ssh-ed25519 AAAA u@h"
      assert second.id == "k2"
      assert second.key_name == "desktop"
    end

    test "unloaded ssh_public_keys association renders as an empty public_keys list" do
      user = struct(SshUsername, username_fixture() |> Map.from_struct() |> Map.delete(:ssh_public_keys))

      assert SshUsernameView.render(user).public_keys == []
    end

    test "public_key summary contains exactly the documented keys" do
      user = username_fixture(%{ssh_public_keys: [public_key()]})

      [summary] = SshUsernameView.render(user).public_keys

      expected_keys = Enum.sort(~w(id key_name public_key inserted_at updated_at)a)
      assert summary |> Map.keys() |> Enum.sort() == expected_keys
    end

    test "public_key summary omits ssh_username_id (top-level user already has id)" do
      # The nested summary intentionally drops the back-reference.
      user = username_fixture(%{ssh_public_keys: [public_key(%{ssh_username_id: "u1"})]})

      [summary] = SshUsernameView.render(user).public_keys

      refute Map.has_key?(summary, :ssh_username_id)
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = SshUsernameView.render(username_fixture())

      expected_keys =
        Enum.sort(~w(id username has_password node_id public_keys inserted_at updated_at)a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
