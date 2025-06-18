# edge_admin/lib/edge_admin/commands.ex
defmodule EdgeAdmin.Commands do
  @moduledoc """
  The Commands context.

  Manages command creation, execution tracking, and provides query helpers
  for the distributed command execution system.
  """

  import Ecto.Query, warn: false
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Commands.{Command, CommandExecution}

  @doc """
  Returns the list of commands.

  ## Examples

      iex> list_commands()
      [%Command{}, ...]

  """
  def list_commands do
    Repo.all(Command)
  end

  @doc """
  Gets a single command.

  Raises `Ecto.NoResultsError` if the Command does not exist.

  ## Examples

      iex> get_command!(123)
      %Command{}

      iex> get_command!(456)
      ** (Ecto.NoResultsError)

  """
  def get_command!(id), do: Repo.get!(Command, id)

  @doc """
  Creates a command.

  ## Examples

      iex> create_command(%{command_text: "echo hello\nls -la"})
      {:ok, %Command{}}

      iex> create_command(%{command_text: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_command(attrs \\ %{}) do
    %Command{}
    |> Command.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command.

  ## Examples

      iex> update_command(command, %{command_text: "new command"})
      {:ok, %Command{}}

      iex> update_command(command, %{command_text: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_command(%Command{} = command, attrs) do
    command
    |> Command.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command.

  ## Examples

      iex> delete_command(command)
      {:ok, %Command{}}

      iex> delete_command(command)
      {:error, %Ecto.Changeset{}}

  """
  def delete_command(%Command{} = command) do
    Repo.delete(command)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking command changes.

  ## Examples

      iex> change_command(command)
      %Ecto.Changeset{data: %Command{}}

  """
  def change_command(%Command{} = command, attrs \\ %{}) do
    Command.changeset(command, attrs)
  end


  @doc """
  Gets a single command_execution.

  Raises `Ecto.NoResultsError` if the Command execution does not exist.

  ## Examples

      iex> get_command_execution!(123)
      %CommandExecution{}

      iex> get_command_execution!(456)
      ** (Ecto.NoResultsError)

  """
  def get_command_execution!(id), do: Repo.get!(CommandExecution, id)

  @doc """
  Creates a command_execution.

  ## Examples

      iex> create_command_execution(%{status: "pending", command_id: cmd_id, node_id: node_id})
      {:ok, %CommandExecution{}}

      iex> create_command_execution(%{status: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command_execution.

  ## Examples

      iex> update_command_execution(command_execution, %{status: "completed", output: "Done"})
      {:ok, %CommandExecution{}}

      iex> update_command_execution(command_execution, %{status: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command_execution.

  ## Examples

      iex> delete_command_execution(command_execution)
      {:ok, %CommandExecution{}}

      iex> delete_command_execution(command_execution)
      {:error, %Ecto.Changeset{}}

  """
  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking command_execution changes.

  ## Examples

      iex> change_command_execution(command_execution)
      %Ecto.Changeset{data: %CommandExecution{}}

  """
  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  @doc """
  Returns a paginated list of command executions with filtering and sorting.

  This function combines filtering/pagination with command execution-specific
  enhancements if needed in the future. It encapsulates the filtering/pagination
  logic including:
  - Which fields can be filtered and sorted
  - Default sorting behavior
  - Any command execution-specific processing

  ## Parameters
  - `params` - Map of query parameters (page, page_size, sort, filters)

  ## Supported Query Parameters
  - `page` - Page number (default: 1)
  - `page_size` - Items per page (default: 20, max: 100)
  - `sort` - Sort specification: "field1:dir1,field2:dir2"

  ## Filterable Fields
  - `status` - Execution status (pending, sent, completed)
  - `target_all` - Boolean filter for system-wide commands
  - `exit_code` - Exit code filter (supports ranges like "gte:0", "ne:0")
  - `command_id` - Filter by command ID
  - `node_id` - Filter by node ID
  - `output` - Text search in output (supports wildcards with *)

  ## Sortable Fields
  - `inserted_at`, `updated_at`, `status`, `sent_at`, `completed_at`, `exit_code`

  ## Examples

      iex> list_command_executions_with_filtering_pagination(%{"page" => "2", "status" => "completed"})
      %FilteringPagination{data: [%CommandExecution{}, ...], ...}

      iex> list_command_executions_with_filtering_pagination(%{"sort" => "status:desc,inserted_at:asc"})
      %FilteringPagination{data: [...], sort: [{:status, :desc}, {:inserted_at, :asc}], ...}

  """
  def list_command_executions_with_filtering_pagination(params \\ %{}) do
    page_result =
      EdgeAdmin.FilteringPagination.paginate(
        CommandExecution,
        params,
        filterable_fields: [:status, :target_all, :exit_code, :command_id, :node_id, :output],
        sortable_fields: [:inserted_at, :updated_at, :status, :sent_at, :completed_at, :exit_code],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # If we need to add any command execution-specific enhancements in the future,
    # we can do them here (similar to how nodes populate virtual fields)
    # For now, just return the page result as-is
    page_result
  end
end
