# edge_admin/test/edge_admin/ssh/validators/ssh_username_validators_test.exs
defmodule EdgeAdmin.Ssh.Validators.SshUsernameValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Validators.SshUsernameValidators

  test "validates usernames" do
    assert SshUsernameValidators.username_error("deploy_user") == :ok
    assert {:error, _} = SshUsernameValidators.username_error("Bad Name")
  end

  test "validates optional passwords" do
    assert SshUsernameValidators.password_error(nil) == :ok
    assert SshUsernameValidators.password_error("securepassword123") == :ok
    assert {:error, _} = SshUsernameValidators.password_error("short")
  end
end
