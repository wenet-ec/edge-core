# edge_admin/lib/edge_admin/commands/forms/update_command_execution_result_form.ex
defmodule EdgeAdmin.Commands.Forms.UpdateCommandExecutionResultForm do
  @moduledoc """
  Form for validating command execution result update inputs from agents.

  State preconditions are enforced by
  `CommandExecutionAcceptsResultCheck` before this form is called.
  """
  use EdgeAdmin.Form

  # Agent-reported terminal statuses. `commands.ex` may further override
  # `:completed` to `:cancelled` based on exit_code 143 (SIGTERM).
  @agent_reported_statuses [:completed, :expired]

  embedded_schema do
    field(:status, Ecto.Enum, values: @agent_reported_statuses)
    field(:output, :string)
    field(:exit_code, :integer)
  end

  @doc "Validates and normalizes command execution result parameters."
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:status, :output, :exit_code])
    |> validate_required([:status])
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp to_map(%__MODULE__{} = form) do
    # Admin owns the authoritative completion timestamp. The Agent's wall
    # clock may be skewed, so never persist its reported `completed_at` value.
    completed_at = DateTime.truncate(DateTime.utc_now(), :second)

    %{
      "status" => form.status,
      "output" => form.output,
      "exit_code" => form.exit_code,
      "completed_at" => completed_at
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
