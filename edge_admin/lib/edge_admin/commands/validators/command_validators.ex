# edge_admin/lib/edge_admin/commands/validators/command_validators.ex
defmodule EdgeAdmin.Commands.Validators.CommandValidators do
  @moduledoc "Pure value-level validators for commands."

  @spec valid_command_text?(term()) :: boolean()
  def valid_command_text?(text) when is_binary(text), do: String.trim(text) != ""
  def valid_command_text?(_text), do: false

  @spec valid_timeout?(term()) :: boolean()
  def valid_timeout?(nil), do: true
  def valid_timeout?(timeout) when is_integer(timeout), do: timeout > 0
  def valid_timeout?(_timeout), do: false

  @spec valid_expiry?(term(), DateTime.t()) :: boolean()
  def valid_expiry?(nil, _now), do: true
  def valid_expiry?(%DateTime{} = expires_at, %DateTime{} = now), do: DateTime.after?(expires_at, now)
  def valid_expiry?(_expires_at, _now), do: false
end
