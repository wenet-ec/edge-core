# edge_admin/lib/edge_admin/ssh/resources/credentials.ex
defmodule EdgeAdmin.Ssh.Resources.Credentials do
  @moduledoc "Explicit SSH credential verification workflow."

  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.PasswordHasher
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Ssh.CredentialMatcher
  alias EdgeAdmin.Ssh.Forms
  alias EdgeAdmin.Ssh.Resources.SshUsernames
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  require Logger

  def verify(node_id, params) do
    with {:ok, attrs} <- Forms.VerifySshCredentialsForm.changeset(params) do
      username = Map.get(attrs, "username")
      password = Map.get(attrs, "password")
      public_key = Map.get(attrs, "public_key")

      ssh_username =
        case SshUsernames.list(%{"node_id" => node_id, "username" => username, "page_size" => "1"}) do
          {:ok, {[value | _], _}} -> value
          _ -> nil
        end

      {verified, auth_method, hash_status} = CredentialMatcher.check_detailed(ssh_username, password, public_key)
      maybe_upgrade(ssh_username, password, hash_status)
      result = if verified, do: :success, else: :failure
      :telemetry.execute([:edge_admin, :ssh, :verification], %{count: 1}, %{result: result, auth_method: auth_method})

      Events.publish(%Catalog.SshUsernameVerified{
        ssh_username: ssh_username && Repo.preload(ssh_username, node: :cluster),
        node_id: node_id,
        attempted_username: username,
        auth_method: auth_method,
        result: result
      })

      {:ok, verified}
    end
  end

  defp maybe_upgrade(%SshUsername{} = username, password, :legacy) when is_binary(password) do
    case username |> SshUsername.changeset(%{password_hash: PasswordHasher.hash(password)}) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("SSH password hash upgrade failed: #{inspect(reason)}")
    end
  end

  defp maybe_upgrade(_, _, _), do: :ok
end
