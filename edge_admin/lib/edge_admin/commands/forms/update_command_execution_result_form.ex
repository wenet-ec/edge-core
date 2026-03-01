# edge_admin/lib/edge_admin/commands/forms/update_command_execution_result_form.ex
defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm do
  @moduledoc """
  Form for validating command execution result update inputs from agents.

  Handles input validation for updating command execution results received from edge agents.
  State preconditions (status, exit_code) are enforced by UpdateExecutionResultCheck before
  this form is called.
  """
  use EdgeAdmin.Form

  embedded_schema do
    field(:output, :string)
    field(:exit_code, :integer)
    field(:completed_at, :utc_datetime)
  end

  @doc """
  Validates and normalizes command execution update parameters.

  ## Parameters
  - `attrs` - Map containing execution result attributes

  ## Validations
  - `output` - Optional, command output text
  - `exit_code` - Optional, must be integer if present
  - `completed_at` - Optional, must be valid ISO8601 datetime if present, defaults to now

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map
  - `{:error, changeset}` - Validation errors
  """
  # Handle wrapped params (from API controller)
  def changeset(%{"command_execution" => command_execution_attrs}) when is_map(command_execution_attrs) do
    changeset(command_execution_attrs)
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:output, :exit_code, :completed_at])
    |> validate_completed_at()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:base, "invalid parameters - expected a map")
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
    completed_at =
      case form.completed_at do
        nil ->
          DateTime.truncate(DateTime.utc_now(), :second)

        timestamp when is_binary(timestamp) ->
          case DateTime.from_iso8601(timestamp) do
            {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
            _ -> DateTime.truncate(DateTime.utc_now(), :second)
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
