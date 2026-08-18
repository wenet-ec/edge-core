# edge_admin/test/edge_admin/ssh/validators/credential_request_validators_test.exs
defmodule EdgeAdmin.Ssh.Validators.CredentialRequestValidatorsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.Validators.CredentialRequestValidators

  test "requires exactly one credential" do
    assert {:error, _} = CredentialRequestValidators.error(nil, nil)
    assert {:error, _} = CredentialRequestValidators.error("password", "public-key")
    assert CredentialRequestValidators.error("password", nil) == :ok
    assert CredentialRequestValidators.error(nil, "public-key") == :ok
  end
end
