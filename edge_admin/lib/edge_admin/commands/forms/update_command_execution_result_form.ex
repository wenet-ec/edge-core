# edge_admin/lib/edge_admin/commands/forms/update_command_execution_result_form.ex
defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm do
  @moduledoc """
  Form for validating command execution result update inputs from agents.

  Handles input validation for updating command execution results received from edge agents.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:output, :string)
    field(:exit_code, :integer)
    field(:completed_at, :utc_datetime)
  end

  @doc """
  Validates and normalizes command execution update parameters.

  Note: Status is automatically set to "completed" by the context after validation.

  ## Validations
  - `output` - Optional, command output text
  - `exit_code` - Optional, must be integer if present
  - `completed_at` - Optional, must be valid ISO8601 datetime if present
  - `current_status` - Validates execution is in "sent" status (passed by context)

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(%{"command_execution" => execution_attrs}, current_status) when is_map(execution_attrs) do
    # Unwrap command_execution
    changeset(execution_attrs, current_status)
  end

  def changeset(attrs, current_status) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:output, :exit_code, :completed_at])
    |> validate_completed_at()
    |> validate_current_status(current_status)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_current_status(changeset, "sent") do
    changeset
  end

  defp validate_current_status(changeset, _current_status) do
    add_error(changeset, :base, "execution is not in 'sent' status and cannot be updated")
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:command_execution, "is required")
     |> apply_action!(:insert)}
  end

  defp validate_completed_at(changeset) do
    validate_change(changeset, :completed_at, fn :completed_at, value ->
      case value do
        nil ->
          []

        timestamp when is_binary(timestamp) ->
          case DateTime.from_iso8601(timestamp) do
            {:ok, _dt, _offset} -> []
            _ -> [completed_at: "must be a valid ISO8601 datetime"]
          end

        %DateTime{} ->
          []

        _ ->
          [completed_at: "must be a valid ISO8601 datetime string or DateTime"]
      end
    end)
  end

  defp to_map(%__MODULE__{} = form) do
    # Parse completed_at if present
    completed_at =
      case form.completed_at do
        nil ->
          DateTime.utc_now() |> DateTime.truncate(:second)

        timestamp when is_binary(timestamp) ->
          case DateTime.from_iso8601(timestamp) do
            {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
            _ -> DateTime.utc_now() |> DateTime.truncate(:second)
          end

        %DateTime{} = dt ->
          DateTime.truncate(dt, :second)
      end

    %{
      "output" => form.output,
      "exit_code" => form.exit_code,
      "completed_at" => completed_at
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
