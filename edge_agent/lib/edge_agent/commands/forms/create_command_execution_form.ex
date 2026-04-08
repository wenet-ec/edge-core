# edge_agent/lib/edge_agent/commands/forms/create_command_execution_form.ex
defmodule EdgeAgent.Commands.Forms.CreateCommandExecutionForm do
  @moduledoc """
  Form for validating command execution creation inputs.

  Handles input validation for creating command executions received from EdgeAdmin.
  This form validates external API inputs before passing to the domain layer.
  """
  use EdgeAgent.Form

  embedded_schema do
    field(:id, :binary_id)
    field(:command_id, :binary_id)
    field(:node_id, :binary_id)
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:expired_at, :utc_datetime)
    field(:status, :string)
    field(:output, :string)
    field(:exit_code, :integer)
    field(:completed_at, :utc_datetime)
  end

  @doc """
  Validates and normalizes command execution creation parameters.

  ## Validations
  - `id` - Required, must be valid UUID
  - `command_id` - Required, must be valid UUID
  - `node_id` - Required, must be valid UUID
  - `command_text` - Required, must not be empty
  - `status` - Required, must be "pending" or "completed"
  - `timeout` - Optional, must be positive integer if present
  - `output` - Optional
  - `exit_code` - Optional, must be integer if present
  - `completed_at` - Optional, must be valid datetime if present

  ## Returns
  - `{:ok, attrs}` - Validated and normalized attributes as a map with string keys
  - `{:error, changeset}` - Validation errors
  """
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :command_id,
      :node_id,
      :command_text,
      :timeout,
      :expired_at,
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
    |> validate_inclusion(:status, ["pending", "completed", "expired"])
    |> validate_timeout()
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
      trimmed = String.trim(command_text)

      if trimmed == "" do
        [command_text: "cannot be empty or only whitespace"]
      else
        []
      end
    end)
  end

  defp validate_timeout(changeset) do
    validate_change(changeset, :timeout, fn :timeout, timeout ->
      cond do
        is_nil(timeout) ->
          []

        timeout <= 0 ->
          [timeout: "must be a positive number (in milliseconds)"]

        true ->
          []
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
      "expired_at" => form.expired_at,
      "status" => form.status,
      "output" => form.output,
      "exit_code" => form.exit_code,
      "completed_at" => form.completed_at
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
