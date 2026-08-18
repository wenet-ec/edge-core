# edge_agent/lib/edge_agent/commands/resources/command_executions.ex
defmodule EdgeAgent.Commands.Resources.CommandExecutions do
  @moduledoc "Persistence operations for local command executions."

  import Ecto.Query, only: [from: 2]

  alias EdgeAgent.Commands.Enums.CommandExecutionStatuses
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Repo

  @spec list() :: [CommandExecution.t()]
  def list, do: Repo.all(CommandExecution)

  @spec get(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @spec create(map()) ::
          {:ok, CommandExecution.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
  def create(attrs) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:id])
  end

  @spec update(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def update(%CommandExecution{} = execution, attrs) do
    execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(CommandExecution.t()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def delete(%CommandExecution{} = execution), do: Repo.delete(execution)

  @spec change(CommandExecution.t(), map()) :: Ecto.Changeset.t()
  def change(%CommandExecution{} = execution, attrs \\ %{}) do
    CommandExecution.changeset(execution, attrs)
  end

  @spec by_status([CommandExecutionStatuses.t()] | CommandExecutionStatuses.t()) ::
          [CommandExecution.t()]
  def by_status(statuses) when is_list(statuses) do
    Repo.all(from(ce in CommandExecution, where: ce.status in ^statuses, order_by: [asc: ce.inserted_at]))
  end

  def by_status(status), do: by_status([status])

  @spec recoverable() :: [CommandExecution.t()]
  def recoverable, do: by_status(CommandExecutionStatuses.recoverable_statuses())

  @spec completed() :: [CommandExecution.t()]
  def completed, do: by_status(:completed)

  @spec claim(CommandExecution.t()) :: {:ok, CommandExecution.t()} | :stale
  def claim(%CommandExecution{id: id}) do
    query = from(ce in CommandExecution, where: ce.id == ^id and ce.status == :pending)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case Repo.update_all(query, set: [status: :running, updated_at: now]) do
      {1, _} ->
        case Repo.get(CommandExecution, id) do
          %CommandExecution{status: :running} = execution -> {:ok, execution}
          _ -> :stale
        end

      {0, _} ->
        :stale
    end
  end

  @spec complete_running(String.t(), String.t() | nil, integer()) :: :ok | :stale
  def complete_running(execution_id, output, exit_code) do
    query = from(ce in CommandExecution, where: ce.id == ^execution_id and ce.status == :running)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    attrs = [
      status: :completed,
      output: output,
      exit_code: exit_code,
      completed_at: now,
      updated_at: now
    ]

    case Repo.update_all(query, set: attrs) do
      {1, _} -> :ok
      {0, _} -> :stale
    end
  end

  @spec cancel_pending_or_running(String.t()) :: :cancelled | :completed | :expired | :not_found
  def cancel_pending_or_running(execution_id) do
    recoverable_statuses = CommandExecutionStatuses.recoverable_statuses()

    query =
      from(ce in CommandExecution,
        where: ce.id == ^execution_id and ce.status in ^recoverable_statuses
      )

    now = DateTime.truncate(DateTime.utc_now(), :second)

    attrs = [
      status: :completed,
      output: "Command cancelled",
      exit_code: 143,
      completed_at: now,
      updated_at: now
    ]

    case Repo.update_all(query, set: attrs) do
      {1, _} ->
        :cancelled

      {0, _} ->
        case Repo.get(CommandExecution, execution_id) do
          nil -> :not_found
          %{status: :completed} -> :completed
          %{status: :expired} -> :expired
          _ -> :not_found
        end
    end
  end
end
