# edge_admin/lib/edge_admin/commands/forms/cancel_execution_form.ex
defmodule EdgeAdmin.Commands.Forms.CancelExecutionForm do
  @moduledoc """
  Form for validating command execution cancellation requests.

  Validates that execution is in a cancellable state (pending or sent).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
  end

  @doc """
  Validates that a command execution can be cancelled.

  ## Parameters
    - current_status: The current status of the execution (passed by context)

  ## Validations
    - Status must be "pending" or "sent"
    - Status cannot be "completed"

  ## Returns
    - `{:ok, %{}}` - Execution can be cancelled
    - `{:error, changeset}` - Validation errors
  """
  def changeset(current_status) when is_binary(current_status) do
    %__MODULE__{}
    |> cast(%{}, [])
    |> validate_cancellable_status(current_status)
    |> apply_action(:insert)
    |> case do
      {:ok, _form} -> {:ok, %{}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp validate_cancellable_status(changeset, status) when status in ["pending", "sent"] do
    changeset
  end

  defp validate_cancellable_status(changeset, status) do
    add_error(
      changeset,
      :status,
      "cannot cancel execution with status '#{status}' - only 'pending' or 'sent' executions can be cancelled"
    )
  end
end
