# edge_admin/test/edge_admin/ssh/forms/verify_ssh_credentials_form_test.exs
defmodule EdgeAdmin.Ssh.Forms.VerifySshCredentialsFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Forms.VerifySshCredentialsForm

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/1 — password auth" do
    test "username + password succeeds" do
      assert {:ok, result} =
               VerifySshCredentialsForm.changeset(%{
                 "username" => "deploy",
                 "password" => "hunter2"
               })

      assert result["username"] == "deploy"
      assert result["password"] == "hunter2"
    end

    test "password is included in result, public_key is excluded" do
      {:ok, result} =
        VerifySshCredentialsForm.changeset(%{"username" => "deploy", "password" => "secret"})

      assert Map.has_key?(result, "password")
      refute Map.has_key?(result, "public_key")
    end
  end

  describe "changeset/1 — public key auth" do
    test "username + public_key succeeds" do
      assert {:ok, result} =
               VerifySshCredentialsForm.changeset(%{
                 "username" => "deploy",
                 "public_key" => "ssh-ed25519 AAAA..."
               })

      assert result["username"] == "deploy"
      assert result["public_key"] == "ssh-ed25519 AAAA..."
    end

    test "public_key is included in result, password is excluded" do
      {:ok, result} =
        VerifySshCredentialsForm.changeset(%{
          "username" => "deploy",
          "public_key" => "ssh-ed25519 AAAA..."
        })

      assert Map.has_key?(result, "public_key")
      refute Map.has_key?(result, "password")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — mutual exclusivity: the core logic
  # ---------------------------------------------------------------------------

  describe "changeset/1 — mutual exclusivity" do
    test "neither password nor public_key returns error" do
      assert {:error, changeset} =
               VerifySshCredentialsForm.changeset(%{"username" => "deploy"})

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "password"
      assert msg =~ "public_key"
    end

    test "both password and public_key returns error" do
      assert {:error, changeset} =
               VerifySshCredentialsForm.changeset(%{
                 "username" => "deploy",
                 "password" => "secret",
                 "public_key" => "ssh-ed25519 AAAA..."
               })

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "only one"
    end

    test "exactly password only passes mutual exclusivity check" do
      assert {:ok, _} =
               VerifySshCredentialsForm.changeset(%{
                 "username" => "deploy",
                 "password" => "secret"
               })
    end

    test "exactly public_key only passes mutual exclusivity check" do
      assert {:ok, _} =
               VerifySshCredentialsForm.changeset(%{
                 "username" => "deploy",
                 "public_key" => "ssh-ed25519 AAAA..."
               })
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — username required
  # ---------------------------------------------------------------------------

  describe "changeset/1 — username required" do
    test "missing username is rejected" do
      assert {:error, changeset} =
               VerifySshCredentialsForm.changeset(%{"password" => "secret"})

      assert %{username: [_msg]} = errors_on(changeset)
    end

    test "empty username is rejected" do
      assert {:error, changeset} =
               VerifySshCredentialsForm.changeset(%{"username" => "", "password" => "secret"})

      assert %{username: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/1 — to_map output" do
    test "nil fields are excluded from result" do
      {:ok, result} =
        VerifySshCredentialsForm.changeset(%{"username" => "deploy", "password" => "secret"})

      refute Map.has_key?(result, "public_key")
    end

    test "username is always present in result" do
      {:ok, result} =
        VerifySshCredentialsForm.changeset(%{"username" => "deploy", "password" => "secret"})

      assert Map.has_key?(result, "username")
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/1 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/1 — invalid params" do
    test "non-map params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        VerifySshCredentialsForm.changeset("bad")
      end
    end

    test "nil params raise (apply_action! in fallback clause)" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        VerifySshCredentialsForm.changeset(nil)
      end
    end
  end
end
