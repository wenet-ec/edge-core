# edge_admin/lib/edge_admin/commands/forms/acknowledge_command_execution_form.ex
defmodule EdgeAdmin.Commands.Forms.AcknowledgeCommandExecutionForm do
  @moduledoc """
  Form for validating command execution acknowledgment from agents.

  Handles validation for agents acknowledging receipt of pending command executions.
  This transitions execution status from "pending" to "sent".
  """
  use EdgeAdmin.Form

  embedded_schema do
    # No fields needed - acknowledgment is just a status transition
  end

  @doc """
  Validates that the execution is in "pending" status and can be acknowledged.

  ## Parameters
  - `attrs` - Map (can be empty, no params needed for acknowledgment)
  - `current_status` - Current status of the execution

  ## Validations
  - `current_status` - Must be "pending"

  ## Returns
  - `{:ok, %{}}` - Empty map (no attributes to update beyond status)
  - `{:error, changeset}` - Validation errors

  ## Examples

      iex> changeset(%{}, "pending")
      {:ok, %{}}

      iex> changeset(%{}, "sent")
      {:error, %Ecto.Changeset{}}
  """
  # Handle wrapped params (from API controller)
  def changeset(%{"command_execution" => command_execution_attrs}, current_status)
      when is_map(command_execution_attrs) do
    # Unwrap command_execution (but we don't need any fields)
    changeset(%{}, current_status)
  end

  def changeset(attrs, current_status) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [])
    |> validate_current_status(current_status)
    |> apply_action(:insert)
    |> case do
      {:ok, _form} -> {:ok, %{}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params, _current_status) do
    {:error,
     %__MODULE__{}
     |> cast(%{}, [])
     |> add_error(:base, "invalid parameters - expected a map")
     |> apply_action!(:insert)}
  end

  # Normal case: execution is in "pending" status and can be acknowledged
  defp validate_current_status(changeset, "pending") do
    changeset
  end

  # All other cases: reject acknowledgment
  defp validate_current_status(changeset, current_status) do
    add_error(
      changeset,
      :base,
      "execution is in '#{current_status}' status and cannot be acknowledged (must be 'pending')"
    )
  end
end
