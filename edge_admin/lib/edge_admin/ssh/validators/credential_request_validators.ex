# edge_admin/lib/edge_admin/ssh/validators/credential_request_validators.ex
defmodule EdgeAdmin.Ssh.Validators.CredentialRequestValidators do
  @moduledoc "Pure validators for SSH credential-verification request shape."

  @spec error(term(), term()) :: :ok | {:error, String.t()}
  def error(nil, nil), do: {:error, "either password or public_key must be provided"}

  def error(password, public_key) when not is_nil(password) and not is_nil(public_key),
    do: {:error, "only one of password or public_key should be provided"}

  def error(_password, _public_key), do: :ok
end
