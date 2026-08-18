# edge_agent/lib/edge_agent/commands/forms/create_command_execution_form.ex
defmodule EdgeAgent.Commands.Forms.CreateCommandExecutionForm do
  @moduledoc """
  Form for validating command execution creation inputs.

  Accepts pending command executions received from Admin before they are stored
  in the local Agent database.
  """
  use EdgeAgent.Form

  alias EdgeAgent.Commands.Enums.CommandExecutionStatuses
  alias EdgeAgent.Commands.Validators.CommandExecutionValidators

  @incoming_statuses CommandExecutionStatuses.incoming_statuses()

  embedded_schema do
    field(:id, :binary_id)
    field(:command_id, :binary_id)
    field(:node_id, :binary_id)
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:expires_at, :utc_datetime)
    field(:status, Ecto.Enum, values: @incoming_statuses)
    field(:output, :string)
    field(:exit_code, :integer)
    field(:completed_at, :utc_datetime)
  end

  @doc """
  Validates and normalizes command execution creation parameters.

  Returns normalized string-keyed attributes or a changeset error.
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :command_id,
      :node_id,
      :command_text,
      :timeout,
      :expires_at,
      :status,
      :output,
      :exit_code,
      :completed_at
    ])
    |> validate_required([:id, :command_id, :node_id, :command_text, :status])
    |> validate_uuid_format(:id)
    |> validate_uuid_format(:command_id)
    |> validate_uuid_format(:node_id)
    |> validate_command_text_format()
    |> validate_timeout()
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

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end

  defp validate_command_text_format(changeset) do
    validate_change(changeset, :command_text, fn :command_text, command_text ->
      if CommandExecutionValidators.valid_command_text?(command_text) do
        []
      else
        [command_text: CommandExecutionValidators.command_text_error()]
      end
    end)
  end

  defp validate_timeout(changeset) do
    validate_change(changeset, :timeout, fn :timeout, timeout ->
      if CommandExecutionValidators.valid_timeout?(timeout) do
        []
      else
        [timeout: CommandExecutionValidators.timeout_error()]
      end
    end)
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "id" => form.id,
      "command_id" => form.command_id,
      "node_id" => form.node_id,
      "command_text" => form.command_text,
      "timeout" => form.timeout,
      "expires_at" => form.expires_at,
      "status" => form.status,
      "output" => form.output,
      "exit_code" => form.exit_code,
      "completed_at" => form.completed_at
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
