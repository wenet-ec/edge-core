# edge_admin/test/edge_admin/ssh/schemas/ssh_public_key_test.exs
defmodule EdgeAdmin.Ssh.Schemas.SshPublicKeyTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  @valid_attrs %{
    "public_key" => "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment",
    "key_name" => "laptop",
    "ssh_username_id" => "0190f1e0-7b2a-7abc-8def-0123456789ab"
  }

  test "changeset accepts a valid SSH public key" do
    assert %Ecto.Changeset{valid?: true} = SshPublicKey.changeset(%SshPublicKey{}, @valid_attrs)
  end

  test "changeset rejects an invalid SSH public key" do
    changeset = SshPublicKey.changeset(%SshPublicKey{}, Map.put(@valid_attrs, "public_key", "not a key"))

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :public_key)
  end
end
