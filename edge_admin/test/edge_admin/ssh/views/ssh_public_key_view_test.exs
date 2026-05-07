# edge_admin/test/edge_admin/ssh/views/ssh_public_key_view_test.exs
defmodule EdgeAdmin.Ssh.Views.SshPublicKeyViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Views.SshPublicKeyView

  defp key_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %SshPublicKey{
      id: "key-uuid-1",
      public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 user@host",
      key_name: "laptop",
      ssh_username_id: "username-uuid-1",
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      key = key_fixture()

      result = SshPublicKeyView.render(key)

      assert result.id == key.id
      assert result.public_key == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 user@host"
      assert result.key_name == "laptop"
      assert result.ssh_username_id == "username-uuid-1"
      assert result.inserted_at == key.inserted_at
      assert result.updated_at == key.updated_at
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = SshPublicKeyView.render(key_fixture())

      expected_keys =
        Enum.sort(~w(id public_key key_name ssh_username_id inserted_at updated_at)a)

      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
