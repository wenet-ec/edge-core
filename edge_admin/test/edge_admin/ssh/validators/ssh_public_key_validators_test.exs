# edge_admin/test/edge_admin/ssh/validators/ssh_public_key_validators_test.exs
defmodule EdgeAdmin.Ssh.Validators.SshPublicKeyValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Validators.SshPublicKeyValidators

  @ed25519_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment"
  @ed25519_key_no_comment "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC"
  @ecdsa256_key "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHIOb8aQOlQE4WbojqM+3s3nt/tOudVdC4P49Q0E41LBi4T9I/EgMMrkat9y9y0Wj+pYTJbGsCbttefkoBZK//M="
  @rsa_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLafo9rqBnzmfQuc/ch17cnnYCvqvRFO0I8qoxm3un+N6eStcfTkfqbuYq5K/JPMgn0SOY48kjYhNwak4wL3/Pe4ekhsmeUrJ7sshxbvsotOxho6G41WvyyRdfH/Ng0D7PtjcXIw/+xvnaehpocefzjmvlBjZFsL8mm6rVt7TFkcF/iGEmIddz4QiabT5CKLSWsUfY9dygYtv8uFKQYg3Hn8ajSGBPT+guC3DVxhpRu5XdddygSgl0h94fuqiq0Tb/a2LG1qWPE9JxfcPj0ZjtGM4dEbYKBYZjps32UnHY3AsM9asigjSxIpeFOKhX31U7Z7oyGL/yku9N7r3dhjD5 user@host"

  test "accepts supported SSH public key algorithms" do
    assert {:ok, "ssh-ed25519"} = SshPublicKeyValidators.validate_key_format(@ed25519_key)
    assert {:ok, "ssh-ed25519"} = SshPublicKeyValidators.validate_key_format(@ed25519_key_no_comment)
    assert {:ok, "ecdsa-sha2-nistp256"} = SshPublicKeyValidators.validate_key_format(@ecdsa256_key)
    assert {:ok, "ssh-rsa"} = SshPublicKeyValidators.validate_key_format(@rsa_key)
  end

  test "trims whitespace around the key" do
    assert {:ok, "ssh-ed25519"} = SshPublicKeyValidators.validate_key_format("  #{@ed25519_key}  ")
  end

  test "rejects malformed keys and unsupported algorithms" do
    assert {:error, _reason} = SshPublicKeyValidators.validate_key_format("not a key")
    assert {:error, _reason} = SshPublicKeyValidators.validate_key_format("")
    assert {:error, _reason} = SshPublicKeyValidators.validate_key_format("ssh-ed25519")
    assert {:error, _reason} = SshPublicKeyValidators.validate_key_format("-----BEGIN OPENSSH PRIVATE KEY-----")
    assert {:error, _reason} = SshPublicKeyValidators.validate_key_format("AAAAC3NzaC1lZDI1NTE5AAAAITest")

    assert {:error, _message} =
             SshPublicKeyValidators.validate_key_format("ssh-dss AAAAC3NzaC1lZDI1NTE5AAAAITest")

    assert {:error, _message} =
             SshPublicKeyValidators.validate_key_format("ssh-unknown AAAAC3NzaC1lZDI1NTE5AAAAItest")

    assert {:error, _message} = SshPublicKeyValidators.validate_key_format("ssh-ed25519 !!!NOT_BASE64!!! comment")

    assert {:error, "invalid base64 key data"} =
             SshPublicKeyValidators.validate_key_format("ssh-ed25519 A")
  end

  test "returns the algorithm on success and a reason on failure" do
    assert {:ok, algorithm} = SshPublicKeyValidators.validate_key_format(@ed25519_key)
    assert algorithm == "ssh-ed25519"

    assert {:error, reason} = SshPublicKeyValidators.validate_key_format("bad")
    assert is_binary(reason)
  end
end
