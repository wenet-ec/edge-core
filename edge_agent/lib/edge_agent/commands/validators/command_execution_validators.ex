# edge_agent/lib/edge_agent/commands/validators/command_execution_validators.ex
defmodule EdgeAgent.Commands.Validators.CommandExecutionValidators do
  @moduledoc """
  Pure value validation for locally tracked command executions.

  These rules are shared by the Admin-ingress Form and the Ecto schema. They
  deliberately do not validate lifecycle status, because the Form and schema
  have different allowed status sets.
  """

  @doc "Returns whether command text contains non-whitespace content."
  @spec valid_command_text?(term()) :: boolean()
  def valid_command_text?(command_text) when is_binary(command_text) do
    String.trim(command_text) != ""
  end

  def valid_command_text?(_command_text), do: false

  @doc "Returns whether a timeout is absent or a positive integer."
  @spec valid_timeout?(term()) :: boolean()
  def valid_timeout?(nil), do: true
  def valid_timeout?(timeout) when is_integer(timeout), do: timeout > 0
  def valid_timeout?(_timeout), do: false

  @doc "Error used when command text is present but contains no command."
  @spec command_text_error() :: String.t()
  def command_text_error, do: "cannot be empty or only whitespace"

  @doc "Error used when timeout is present but is not positive."
  @spec timeout_error() :: String.t()
  def timeout_error, do: "must be a positive number (in milliseconds)"
end
