# edge_admin/test/edge_admin/ssh/forms/create_ssh_username_form_test.exs
defmodule EdgeAdmin.Ssh.Forms.CreateSshUsernameFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Forms.CreateSshUsernameForm

  # ---------------------------------------------------------------------------
  # fixtures
  # ---------------------------------------------------------------------------

  @valid_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP5B9NcAkWDeryLofh8tn2lNrOnpkCuMUuY5Ytj4VMJC test-comment"

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{"username" => "deploy"}, overrides)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — valid cases" do
    test "username only (no password, no keys) succeeds" do
      assert {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs())
      assert result["username"] == "deploy"
    end

    test "username with password succeeds" do
      assert {:ok, result} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => "securepassword123"}))

      assert result["username"] == "deploy"
      assert result["password"] == "securepassword123"
    end

    test "username with nested public_keys succeeds" do
      attrs =
        valid_attrs(%{
          "public_keys" => [%{"key_name" => "laptop", "public_key" => @valid_key}]
        })

      assert {:ok, result} = CreateSshUsernameForm.changeset(attrs)
      assert [key] = result["public_keys"]
      assert key["key_name"] == "laptop"
    end

    test "wrapped ssh_username params are unwrapped (atom key)" do
      assert {:ok, result} =
               CreateSshUsernameForm.changeset(%{ssh_username: valid_attrs()})

      assert result["username"] == "deploy"
    end

    test "3-character username is valid (min boundary)" do
      assert {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs(%{"username" => "abc"}))
      assert result["username"] == "abc"
    end

    test "32-character username is valid (max boundary)" do
      username = String.duplicate("a", 32)
      assert {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs(%{"username" => username}))
      assert result["username"] == username
    end

    test "12-character password is valid (min boundary)" do
      assert {:ok, result} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => "abcdefghijkl"}))

      assert result["password"] == "abcdefghijkl"
    end

    test "128-character password is valid (max boundary)" do
      password = String.duplicate("a", 128)

      assert {:ok, result} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => password}))

      assert result["password"] == password
    end

    test "multiple valid public_keys are all returned" do
      second_key =
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDLafo9rqBnzmfQuc/ch17cnnYCvqvRFO0I8qoxm3un+N6eStcfTkfqbuYq5K/JPMgn0SOY48kjYhNwak4wL3/Pe4ekhsmeUrJ7sshxbvsotOxho6G41WvyyRdfH/Ng0D7PtjcXIw/+xvnaehpocefzjmvlBjZFsL8mm6rVt7TFkcF/iGEmIddz4QiabT5CKLSWsUfY9dygYtv8uFKQYg3Hn8ajSGBPT+guC3DVxhpRu5XdddygSgl0h94fuqiq0Tb/a2LG1qWPE9JxfcPj0ZjtGM4dEbYKBYZjps32UnHY3AsM9asigjSxIpeFOKhX31U7Z7oyGL/yku9N7r3dhjD5 user@host"

      attrs =
        valid_attrs(%{
          "public_keys" => [
            %{"key_name" => "laptop", "public_key" => @valid_key},
            %{"key_name" => "server", "public_key" => second_key}
          ]
        })

      assert {:ok, result} = CreateSshUsernameForm.changeset(attrs)
      assert length(result["public_keys"]) == 2
    end

    test "empty public_keys list succeeds and is excluded from result" do
      attrs = valid_attrs(%{"public_keys" => []})
      assert {:ok, result} = CreateSshUsernameForm.changeset(attrs)
      refute Map.has_key?(result, "public_keys")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — username validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — username validation" do
    test "missing username is rejected" do
      assert {:error, changeset} = CreateSshUsernameForm.changeset(%{})
      assert %{username: [_msg]} = errors_on(changeset)
    end

    test "2-character username is too short" do
      assert {:error, changeset} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"username" => "ab"}))

      assert %{username: [_msg]} = errors_on(changeset)
    end

    test "33-character username exceeds max length" do
      username = String.duplicate("a", 33)

      assert {:error, changeset} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"username" => username}))

      assert %{username: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — password validation
  # ---------------------------------------------------------------------------

  describe "changeset/1 — password validation" do
    test "nil password is allowed (optional field)" do
      assert {:ok, result} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => nil}))

      refute Map.has_key?(result, "password")
    end

    test "absent password is allowed (optional field)" do
      assert {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs())
      refute Map.has_key?(result, "password")
    end

    test "11-character password is too short" do
      assert {:error, changeset} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => "tooshort123"}))

      assert %{password: [_msg]} = errors_on(changeset)
    end

    test "129-character password exceeds max length" do
      password = String.duplicate("a", 129)

      assert {:error, changeset} =
               CreateSshUsernameForm.changeset(valid_attrs(%{"password" => password}))

      assert %{password: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil password is excluded from result" do
      {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs())
      refute Map.has_key?(result, "password")
    end

    test "provided password is included in result" do
      {:ok, result} =
        CreateSshUsernameForm.changeset(valid_attrs(%{"password" => "securepassword123"}))

      assert Map.has_key?(result, "password")
    end

    test "public_keys absent from result when none provided" do
      {:ok, result} = CreateSshUsernameForm.changeset(valid_attrs())
      refute Map.has_key?(result, "public_keys")
    end

    test "public_keys present in result when valid keys provided" do
      attrs = valid_attrs(%{"public_keys" => [%{"key_name" => "k", "public_key" => @valid_key}]})
      {:ok, result} = CreateSshUsernameForm.changeset(attrs)
      assert Map.has_key?(result, "public_keys")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — nested public key validation and indexed errors
  # ---------------------------------------------------------------------------

  describe "changeset/1 — nested public key validation" do
    test "invalid nested key returns error" do
      attrs =
        valid_attrs(%{
          "public_keys" => [%{"key_name" => "laptop", "public_key" => "not-a-key"}]
        })

      assert {:error, changeset} = CreateSshUsernameForm.changeset(attrs)
      assert %{public_keys: [_msg]} = errors_on(changeset)
    end

    test "invalid key error message includes key index" do
      attrs =
        valid_attrs(%{
          "public_keys" => [%{"key_name" => "laptop", "public_key" => "not-a-key"}]
        })

      {:error, changeset} = CreateSshUsernameForm.changeset(attrs)
      [error_msg] = errors_on(changeset).public_keys
      assert error_msg =~ "0"
    end

    test "second invalid key error includes index 1" do
      attrs =
        valid_attrs(%{
          "public_keys" => [
            %{"key_name" => "good", "public_key" => @valid_key},
            %{"key_name" => "bad", "public_key" => "not-a-key"}
          ]
        })

      {:error, changeset} = CreateSshUsernameForm.changeset(attrs)
      [error_msg] = errors_on(changeset).public_keys
      assert error_msg =~ "1"
    end

    test "mix of valid and invalid keys returns error (all-or-nothing)" do
      attrs =
        valid_attrs(%{
          "public_keys" => [
            %{"key_name" => "good", "public_key" => @valid_key},
            %{"key_name" => "bad", "public_key" => "not-a-key"}
          ]
        })

      assert {:error, _changeset} = CreateSshUsernameForm.changeset(attrs)
    end

    test "nested key missing key_name returns error" do
      attrs =
        valid_attrs(%{
          "public_keys" => [%{"public_key" => @valid_key}]
        })

      assert {:error, changeset} = CreateSshUsernameForm.changeset(attrs)
      assert %{public_keys: [msg]} = errors_on(changeset)
      assert msg =~ "key_name"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateSshUsernameForm.changeset("bad")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        CreateSshUsernameForm.changeset(nil)
      end
    end
  end
end
