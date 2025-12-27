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

  ## Parameters
  - `attrs` - Map containing execution result attributes
  - `current_status` - Current status of the execution
  - `current_exit_code` - Current exit code of the execution (nil if not set)

  ## Validations
  - `output` - Optional, command output text
  - `exit_code` - Optional, must be integer if present
  - `completed_at` - Optional, must be valid ISO8601 datetime if present, defaults to now
  - `current_status` - Must be "sent" or "completed" with exit_code 143 (cancelled race condition)
  - `current_exit_code` - Used to detect race condition (cancelled executions can be overwritten)

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors

  ## Examples

      iex> changeset(%{"output" => "Hello", "exit_code" => 0}, "sent", nil)
      {:ok, %{"output" => "Hello", "exit_code" => 0, "completed_at" => ~U[...]}}

      iex> changeset(%{"output" => "Cancelled", "exit_code" => 1}, "completed", 143)
      {:ok, %{"output" => "Cancelled", "exit_code" => 1, "completed_at" => ~U[...]}}

      iex> changeset(%{"output" => "Error"}, "completed", 1)
      {:error, %Ecto.Changeset{}}
  """
  def changeset(attrs, current_status, current_exit_code) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:output, :exit_code, :completed_at])
    |> validate_completed_at()
    |> validate_current_status(current_status, current_exit_code)
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params, _current_status, _current_exit_code) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:base, "invalid parameters - expected a map")
     |> apply_action!(:insert)}
  end

  # Normal case: execution is in "sent" status
  defp validate_current_status(changeset, "sent", _current_exit_code) do
    changeset
  end

  # Race condition: execution was cancelled (completed with exit_code 143) but command actually ran
  # Allow agent to overwrite with actual results
  defp validate_current_status(changeset, "completed", 143) do
    changeset
  end

  # All other cases: reject update
  defp validate_current_status(changeset, current_status, current_exit_code) do
    add_error(
      changeset,
      :base,
      "execution is in '#{current_status}' status (exit_code: #{inspect(current_exit_code)}) and cannot be updated"
    )
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
