# edge_admin/test/edge_admin/ssh/schemas/ssh_public_key_test.exs
defmodule EdgeAdmin.Ssh.Schemas.SshPublicKeyTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Schemas.SshPublicKey

  # ---------------------------------------------------------------------------
  # Real SSH public key fixtures (generated, not sensitive)
  # ---------------------------------------------------------------------------

  @ed25519_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment"
  @ed25519_key_no_comment "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC"
  @ecdsa256_key "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHIOb8aQOlQE4WbojqM+3s3nt/tOudVdC4P49Q0E41LBi4T9I/EgMMrkat9y9y0Wj+pYTJbGsCbttefkoBZK//M="
  @rsa_key "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLafo9rqBnzmfQuc/ch17cnnYCvqvRFO0I8qoxm3un+N6eStcfTkfqbuYq5K/JPMgn0SOY48kjYhNwak4wL3/Pe4ekhsmeUrJ7sshxbvsotOxho6G41WvyyRdfH/Ng0D7PtjcXIw/+xvnaehpocefzjmvlBjZFsL8mm6rVt7TFkcF/iGEmIddz4QiabT5CKLSWsUfY9dygYtv8uFKQYg3Hn8ajSGBPT+guC3DVxhpRu5XdddygSgl0h94fuqiq0Tb/a2LG1qWPE9JxfcPj0ZjtGM4dEbYKBYZjps32UnHY3AsM9asigjSxIpeFOKhX31U7Z7oyGL/yku9N7r3dhjD5 user@host"

  # ---------------------------------------------------------------------------
  # validate_key_format/1 — supported algorithms
  # ---------------------------------------------------------------------------

  describe "validate_key_format/1 — supported algorithms" do
    test "ssh-ed25519 key is accepted" do
      assert {:ok, "ssh-ed25519"} = SshPublicKey.validate_key_format(@ed25519_key)
    end

    test "ssh-ed25519 key without comment is accepted" do
      assert {:ok, "ssh-ed25519"} = SshPublicKey.validate_key_format(@ed25519_key_no_comment)
    end

    test "ecdsa-sha2-nistp256 key is accepted" do
      assert {:ok, "ecdsa-sha2-nistp256"} = SshPublicKey.validate_key_format(@ecdsa256_key)
    end

    test "ssh-rsa key is accepted" do
      assert {:ok, "ssh-rsa"} = SshPublicKey.validate_key_format(@rsa_key)
    end

    test "key with leading/trailing whitespace is accepted (trimmed)" do
      assert {:ok, "ssh-ed25519"} =
               SshPublicKey.validate_key_format("  #{@ed25519_key}  ")
    end
  end

  # ---------------------------------------------------------------------------
  # validate_key_format/1 — format failures
  # ---------------------------------------------------------------------------

  describe "validate_key_format/1 — invalid format" do
    test "plain text is rejected" do
      assert {:error, reason} = SshPublicKey.validate_key_format("not a key")
      assert is_binary(reason)
    end

    test "empty string is rejected" do
      assert {:error, _reason} = SshPublicKey.validate_key_format("")
    end

    test "only algorithm with no key data is rejected" do
      assert {:error, _reason} = SshPublicKey.validate_key_format("ssh-ed25519")
    end

    test "private key format is rejected" do
      assert {:error, _reason} =
               SshPublicKey.validate_key_format("-----BEGIN OPENSSH PRIVATE KEY-----")
    end

    test "key with no algorithm prefix is rejected" do
      # Just raw base64 data
      assert {:error, _reason} =
               SshPublicKey.validate_key_format("AAAAC3NzaC1lZDI1NTE5AAAAITest")
    end
  end

  # ---------------------------------------------------------------------------
  # validate_key_format/1 — unsupported algorithms
  # ---------------------------------------------------------------------------

  describe "validate_key_format/1 — unsupported algorithms" do
    test "ssh-dss (DSA) is rejected as unsupported algorithm" do
      # Syntactically valid format but DSA is not in supported list
      fake_dsa = "ssh-dss AAAAB3NzaC1kc3MAAACBAP fake-data-here"

      case SshPublicKey.validate_key_format(fake_dsa) do
        {:error, reason} ->
          # Either format error or unsupported algorithm error — both acceptable
          assert is_binary(reason)

        {:ok, _} ->
          flunk("Expected DSA key to be rejected")
      end
    end

    test "unknown algorithm prefix returns error" do
      assert {:error, _reason} =
               SshPublicKey.validate_key_format("ssh-unknown AAAAC3NzaC1lZDI1NTE5AAAAItest")
    end
  end

  # ---------------------------------------------------------------------------
  # validate_key_format/1 — bad base64
  # ---------------------------------------------------------------------------

  describe "validate_key_format/1 — invalid base64 key data" do
    test "key with invalid base64 characters is rejected" do
      bad_key = "ssh-ed25519 !!!NOT_BASE64!!! comment"
      assert {:error, _reason} = SshPublicKey.validate_key_format(bad_key)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_key_format/1 — return value
  # ---------------------------------------------------------------------------

  describe "validate_key_format/1 — return value" do
    test "returns {:ok, algorithm} on success" do
      assert {:ok, algorithm} = SshPublicKey.validate_key_format(@ed25519_key)
      assert algorithm == "ssh-ed25519"
    end

    test "returns {:error, binary_reason} on failure" do
      assert {:error, reason} = SshPublicKey.validate_key_format("bad")
      assert is_binary(reason)
    end
  end

  # ---------------------------------------------------------------------------
  # supported_algorithms/0
  # ---------------------------------------------------------------------------

  describe "supported_algorithms/0" do
    test "returns a list of strings" do
      algos = SshPublicKey.supported_algorithms()
      assert is_list(algos)
      assert Enum.all?(algos, &is_binary/1)
    end

    test "includes ssh-ed25519" do
      assert "ssh-ed25519" in SshPublicKey.supported_algorithms()
    end

    test "includes ssh-rsa" do
      assert "ssh-rsa" in SshPublicKey.supported_algorithms()
    end

    test "includes all three ecdsa variants" do
      algos = SshPublicKey.supported_algorithms()
      assert "ecdsa-sha2-nistp256" in algos
      assert "ecdsa-sha2-nistp384" in algos
      assert "ecdsa-sha2-nistp521" in algos
    end
  end
end
