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

  @valid_statuses ["pending", "sent", "completed"]

  @doc """
  Returns the list of valid statuses for command executions.
  """
  def valid_statuses, do: @valid_statuses

  # ====================================================================
  # Command CRUD Operations
  # ====================================================================

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

      iex> create_command(%{commands: ["echo hello", "ls -la"]})
      {:ok, %Command{}}

      iex> create_command(%{commands: []})
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

      iex> update_command(command, %{commands: ["new command"]})
      {:ok, %Command{}}

      iex> update_command(command, %{commands: []})
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

  # ====================================================================
  # CommandExecution CRUD Operations
  # ====================================================================

  @doc """
  Returns the list of command_executions.

  ## Examples

      iex> list_command_executions()
      [%CommandExecution{}, ...]

  """
  def list_command_executions do
    Repo.all(CommandExecution)
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

  # ====================================================================
  # Query Helpers
  # ====================================================================

  @doc """
  Returns command executions filtered by status.

  ## Examples

      iex> list_command_executions_by_status("pending")
      [%CommandExecution{status: "pending"}, ...]

  """
  def list_command_executions_by_status(status) when status in @valid_statuses do
    from(ce in CommandExecution, where: ce.status == ^status)
    |> Repo.all()
  end

  @doc """
  Returns pending command executions for a specific node, ordered by creation time.

  ## Examples

      iex> list_pending_executions_for_node(node_id)
      [%CommandExecution{status: "pending"}, ...]

  """
  def list_pending_executions_for_node(node_id) do
    from(ce in CommandExecution,
      where: ce.node_id == ^node_id and ce.status == "pending",
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of pending executions for a specific node.

  ## Examples

      iex> count_pending_executions_for_node(node_id)
      3

  """
  def count_pending_executions_for_node(node_id) do
    from(ce in CommandExecution,
      where: ce.node_id == ^node_id and ce.status == "pending",
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Checks if a node has any pending command executions.

  ## Examples

      iex> has_pending_executions?(node_id)
      true

  """
  def has_pending_executions?(node_id) do
    count_pending_executions_for_node(node_id) > 0
  end

  @doc """
  Returns pending executions grouped by node, ordered for FIFO processing.
  Used by CommandRetrier worker.

  ## Examples

      iex> list_pending_executions_by_node()
      [%CommandExecution{node_id: node1}, %CommandExecution{node_id: node2}, ...]

  """
  def list_pending_executions_by_node do
    from(ce in CommandExecution,
      where: ce.status == "pending",
      order_by: [asc: ce.node_id, asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns the oldest pending execution for a specific node.
  Used by CommandRetrier for FIFO ordering.

  ## Examples

      iex> get_oldest_pending_execution_for_node(node_id)
      %CommandExecution{}

      iex> get_oldest_pending_execution_for_node(node_id)
      nil

  """
  def get_oldest_pending_execution_for_node(node_id) do
    from(ce in CommandExecution,
      where: ce.node_id == ^node_id and ce.status == "pending",
      order_by: [asc: ce.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns command executions with optional filtering.

  ## Options
  - `:command_id` - Filter by command ID
  - `:node_id` - Filter by node ID
  - `:status` - Filter by status

  ## Examples

      iex> list_command_executions_with_filters(command_id: cmd_id)
      [%CommandExecution{}, ...]

      iex> list_command_executions_with_filters(node_id: node_id, status: "completed")
      [%CommandExecution{}, ...]

  """
  def list_command_executions_with_filters(opts \\ []) do
    CommandExecution
    |> apply_execution_filters(opts)
    |> order_by([ce], desc: ce.inserted_at)
    |> Repo.all()
  end

  defp apply_execution_filters(query, []), do: query

  defp apply_execution_filters(query, [{:command_id, command_id} | rest]) do
    query
    |> where([ce], ce.command_id == ^command_id)
    |> apply_execution_filters(rest)
  end

  defp apply_execution_filters(query, [{:node_id, node_id} | rest]) do
    query
    |> where([ce], ce.node_id == ^node_id)
    |> apply_execution_filters(rest)
  end

  defp apply_execution_filters(query, [{:status, status} | rest]) when status in @valid_statuses do
    query
    |> where([ce], ce.status == ^status)
    |> apply_execution_filters(rest)
  end

  defp apply_execution_filters(query, [_invalid | rest]) do
    apply_execution_filters(query, rest)
  end
end
