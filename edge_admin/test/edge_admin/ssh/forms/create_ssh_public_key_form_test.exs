# edge_admin/test/edge_admin/ssh/forms/create_ssh_public_key_form_test.exs
defmodule EdgeAdmin.Ssh.Forms.CreateSshPublicKeyFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Forms.CreateSshPublicKeyForm

  # ---------------------------------------------------------------------------
  # fixtures
  # ---------------------------------------------------------------------------

  @valid_ed25519 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment"
  @valid_rsa "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLafo9rqBnzmfQuc/ch17cnnYCvqvRFO0I8qoxm3un+N6eStcfTkfqbuYq5K/JPMgn0SOY48kjYhNwak4wL3/Pe4ekhsmeUrJ7sshxbvsotOxho6G41WvyyRdfH/Ng0D7PtjcXIw/+xvnaehpocefzjmvlBjZFsL8mm6rVt7TFkcF/iGEmIddz4QiabT5CKLSWsUfY9dygYtv8uFKQYg3Hn8ajSGBPT+guC3DVxhpRu5XdddygSgl0h94fuqiq0Tb/a2LG1qWPE9JxfcPj0ZjtGM4dEbYKBYZjps32UnHY3AsM9asigjSxIpeFOKhX31U7Z7oyGL/yku9N7r3dhjD5 user@host"
  @valid_ecdsa "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHIOb8aQOlQE4WbojqM+3s3nt/tOudVdC4P49Q0E41LBi4T9I/EgMMrkat9y9y0Wj+pYTJbGsCbttefkoBZK//M="

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{"key_name" => "my-laptop", "public_key" => @valid_ed25519}, overrides)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "valid ed25519 key succeeds" do
      assert {:ok, result} = CreateSshPublicKeyForm.changeset(valid_attrs())
      assert result["key_name"] == "my-laptop"
      assert result["public_key"] == @valid_ed25519
    end

    test "valid rsa key succeeds" do
      assert {:ok, result} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => @valid_rsa}))

      assert result["public_key"] == @valid_rsa
    end

    test "valid ecdsa key succeeds" do
      assert {:ok, result} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => @valid_ecdsa}))

      assert result["public_key"] == @valid_ecdsa
    end

    test "key with leading/trailing whitespace is accepted" do
      assert {:ok, _} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => "  #{@valid_ed25519}  "}))
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/1 — required fields" do
    test "missing key_name is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(%{"public_key" => @valid_ed25519})

      assert %{key_name: [_msg]} = errors_on(changeset)
    end

    test "missing public_key is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(%{"key_name" => "my-laptop"})

      assert %{public_key: [_msg]} = errors_on(changeset)
    end

    test "empty public_key is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => ""}))

      assert %{public_key: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — SSH key format validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — SSH key format validation" do
    test "plain text is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => "not a key"}))

      assert %{public_key: [_msg]} = errors_on(changeset)
    end

    test "private key format is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(
                 valid_attrs(%{
                   "public_key" => "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA...\n-----END OPENSSH PRIVATE KEY-----"
                 })
               )

      assert %{public_key: [_msg]} = errors_on(changeset)
    end

    test "key with invalid base64 data is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => "ssh-ed25519 !!!NOT_BASE64!!! comment"}))

      assert %{public_key: [_msg]} = errors_on(changeset)
    end

    test "algorithm only, no key data, is rejected" do
      assert {:error, changeset} =
               CreateSshPublicKeyForm.changeset(valid_attrs(%{"public_key" => "ssh-ed25519"}))

      assert %{public_key: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "result contains key_name and public_key" do
      {:ok, result} = CreateSshPublicKeyForm.changeset(valid_attrs())
      assert Map.has_key?(result, "key_name")
      assert Map.has_key?(result, "public_key")
    end

    test "no extra keys in result" do
      {:ok, result} = CreateSshPublicKeyForm.changeset(valid_attrs())
      assert result |> Map.keys() |> Enum.sort() == ["key_name", "public_key"]
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateSshPublicKeyForm.changeset("bad")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateSshPublicKeyForm.changeset(nil)
      end
    end
  end
end
