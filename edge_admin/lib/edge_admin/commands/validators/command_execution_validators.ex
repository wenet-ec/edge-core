# edge_admin/lib/edge_admin/commands/validators/command_execution_validators.ex
defmodule EdgeAdmin.Commands.Validators.CommandExecutionValidators do
  @moduledoc "Pure value-level validators for command execution results."

  @spec valid_completed_at?(term()) :: boolean()
  def valid_completed_at?(nil), do: true
  def valid_completed_at?(%DateTime{}), do: true

  def valid_completed_at?(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, _datetime, _offset} -> true
      _ -> false
    end
  end

  def valid_completed_at?(_timestamp), do: false
end
