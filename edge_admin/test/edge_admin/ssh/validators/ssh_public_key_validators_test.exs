# edge_admin/test/edge_admin/ssh/validators/ssh_public_key_validators_test.exs
defmodule EdgeAdmin.Ssh.Validators.SshPublicKeyValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Validators.SshPublicKeyValidators

  @key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment"

  test "validates supported public keys" do
    assert {:ok, "ssh-ed25519"} = SshPublicKeyValidators.validate_key_format(@key)
  end

  test "rejects unsupported algorithms and malformed key data" do
    assert {:error, _message} =
             SshPublicKeyValidators.validate_key_format("ssh-dss AAAAC3NzaC1lZDI1NTE5AAAAITest")

    assert {:error, "invalid base64 key data"} =
             SshPublicKeyValidators.validate_key_format("ssh-ed25519 A")
  end
end
