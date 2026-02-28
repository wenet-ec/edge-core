# edge_admin/test/edge_admin/ssh/schemas/ssh_username_test.exs
defmodule EdgeAdmin.Ssh.Schemas.SshUsernameTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Schemas.SshUsername

  # ---------------------------------------------------------------------------
  # has_password?/1
  # ---------------------------------------------------------------------------

  describe "has_password?/1" do
    test "returns false when password_hash is nil" do
      assert SshUsername.has_password?(%SshUsername{password_hash: nil}) == false
    end

    test "returns true when password_hash is set" do
      assert SshUsername.has_password?(%SshUsername{password_hash: "$argon2id$..."}) == true
    end

    test "returns true for any non-nil hash value" do
      assert SshUsername.has_password?(%SshUsername{password_hash: "any_string"}) == true
    end
  end
end
