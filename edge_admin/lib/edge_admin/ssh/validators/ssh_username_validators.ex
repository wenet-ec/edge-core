# edge_admin/lib/edge_admin/ssh/validators/ssh_username_validators.ex
defmodule EdgeAdmin.Ssh.Validators.SshUsernameValidators do
  @moduledoc "Pure value-level validators for SSH usernames and passwords."

  alias EdgeAdmin.Naming

  @spec username_error(term()) :: :ok | {:error, String.t()}
  def username_error(username) when is_binary(username) do
    cond do
      byte_size(username) < Naming.ssh_username_min_length() ->
        {:error, "should be at least #{Naming.ssh_username_min_length()} character(s)"}

      byte_size(username) > Naming.ssh_username_max_length() ->
        {:error, "should be at most #{Naming.ssh_username_max_length()} character(s)"}

      not Regex.match?(Naming.ssh_username_regex(), username) ->
        {:error,
         "must start with a letter or underscore and contain only lowercase letters, digits, hyphens, or underscores"}

      true ->
        :ok
    end
  end

  def username_error(_username), do: {:error, "has invalid format"}

  @spec password_error(term()) :: :ok | {:error, String.t()}
  def password_error(nil), do: :ok

  def password_error(password) when is_binary(password) do
    cond do
      byte_size(password) < Naming.ssh_password_min_length() ->
        {:error, "should be at least #{Naming.ssh_password_min_length()} character(s)"}

      byte_size(password) > Naming.ssh_password_max_length() ->
        {:error, "should be at most #{Naming.ssh_password_max_length()} character(s)"}

      true ->
        :ok
    end
  end

  def password_error(_password), do: {:error, "has invalid format"}
end
