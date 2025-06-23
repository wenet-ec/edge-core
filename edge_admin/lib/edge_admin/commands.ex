# edge_admin/lib/edge_admin/commands.ex
defmodule EdgeAdmin.Commands do
  @moduledoc """
  The Commands context.

  Manages command creation, execution tracking, and provides query helpers
  for the distributed command execution system.
  """

  import Ecto.Query, warn: false
  alias EdgeAdmin.Repo
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Commands.{Command, CommandExecution}

  alias EdgeAdmin.Commands.Workers.{
    AllNodesDispatchWorker,
    TargetedDispatchWorker
  }

  require Logger

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
  Returns a paginated list of commands with filtering and sorting.

  ## Parameters
  - `params` - Map of query parameters (page, page_size, sort, filters)

  ## Supported Query Parameters
  - `page` - Page number (default: 1)
  - `page_size` - Items per page (default: 20, max: 100)
  - `sort` - Sort specification: "field1:dir1,field2:dir2"

  ## Filterable Fields
  - `command_text` - Text search in command text (supports wildcards with *)

  ## Sortable Fields
  - `inserted_at`, `updated_at`

  ## Examples

      iex> list_commands_with_filtering_pagination(%{"page" => "2", "command_text" => "*nginx*"})
      %FilteringPagination{data: [%Command{}, ...], ...}

      iex> list_commands_with_filtering_pagination(%{"sort" => "inserted_at:desc"})
      %FilteringPagination{data: [...], sort: [{:inserted_at, :desc}], ...}

  """
  def list_commands_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      Command,
      params,
      filterable_fields: [:command_text],
      sortable_fields: [:inserted_at, :updated_at],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
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
    FilteringPagination.paginate(
      CommandExecution,
      params,
      filterable_fields: [:status, :target_all, :exit_code, :command_id, :node_id, :output],
      sortable_fields: [:inserted_at, :updated_at, :status, :sent_at, :completed_at, :exit_code],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
  end

  @doc """
  Creates a command and dispatches executions based on target specification.
  """
  def create_command_and_dispatch_executions(attrs) do
    # First create the command
    case create_command(attrs) do
      {:ok, command} ->
        # Dispatch executions based on target specification
        dispatch_executions(command, attrs)
        {:ok, command}

      {:error, changeset} ->
        Logger.error("Failed to create command: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp dispatch_executions(command, %{"target_all" => true}) do
    # For target_all, enqueue background worker to create mass executions
    %{command_id: command.id}
    |> AllNodesDispatchWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue AllNodesDispatchWorker: #{inspect(reason)}")
    end
  end

  defp dispatch_executions(command, %{"target_nodes" => target_nodes})
       when is_list(target_nodes) do
    # For specific targets, enqueue worker for immediate dispatch attempt
    %{
      command_id: command.id,
      target_node_ids: target_nodes
    }
    |> TargetedDispatchWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue TargetedDispatchWorker: #{inspect(reason)}")
    end
  end

  defp dispatch_executions(command, attrs) do
    Logger.warning(
      "No target specification found for command #{command.id}, attrs: #{inspect(attrs)}"
    )

    :ok
  end

  @doc """
  Creates command executions for all nodes with pending status.
  """
  def create_executions_for_all_nodes(command_id) do
    # First get the command to access command_text
    command = get_command!(command_id)

    # Get all nodes using existing pagination function with large page size
    page_result =
      Nodes.list_nodes_with_filtering_pagination(%{
        "page_size" => "1000"
      })

    # Create executions for all nodes
    executions =
      Enum.map(page_result.data, fn node ->
        %{
          id: Ecto.UUID.generate(),
          command_id: command_id,
          node_id: node.id,
          target_all: true,
          status: "pending",
          command_text: command.command_text,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      end)

    # Bulk insert all executions
    try do
      {count, executions} = Repo.insert_all(CommandExecution, executions, returning: true)
      Logger.info("Successfully created #{count} command executions")
      {:ok, executions}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  @doc """
  Creates executions for specific target nodes and attempts immediate delivery.
  """
  def create_executions_for_target_nodes(command_id, node_ids) do
    # First get the command to access command_text
    command = get_command!(command_id)

    # Get nodes using existing get_nodes_by_ids function from Nodes context
    nodes = Nodes.get_nodes_by_ids(node_ids)

    results =
      Enum.map(nodes, fn
        {:ok, node} ->
          # Create execution record
          execution_attrs = %{
            command_id: command_id,
            node_id: node.id,
            target_all: false,
            status: "pending",
            command_text: command.command_text
          }

          case create_command_execution(execution_attrs) do
            {:ok, execution} ->
              # Attempt immediate delivery
              case attempt_execution_delivery(execution, node) do
                :ok ->
                  {:ok, execution}

                :error ->
                  Logger.warning(
                    "Failed to deliver execution #{execution.id} to node #{node.id}, will retry later"
                  )

                  {:ok, execution}
              end

            {:error, changeset} ->
              Logger.error(
                "Failed to create execution for node #{node.id}: #{inspect(changeset.errors)}"
              )

              {:error, changeset}
          end

        {:error, reason} = error ->
          Logger.error("Failed to get node: #{inspect(reason)}")
          error
      end)

    # Separate successful and failed results
    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    if Enum.empty?(errors) do
      {:ok, Enum.map(successes, fn {:ok, execution} -> execution end)}
    else
      {:partial_success, %{successes: successes, errors: errors}}
    end
  end

  @doc """
  Attempts to deliver a command execution to a node.

  Updates execution status to 'sent' if successful, keeps as 'pending' if failed.
  Reuses existing get_node! function if node is not provided.
  """
  def attempt_execution_delivery(execution, node \\ nil) do
    # Get node info if not provided, reusing existing function
    node =
      case node do
        nil ->
          try do
            Nodes.get_node!(execution.node_id)
          rescue
            Ecto.NoResultsError ->
              Logger.error("Node #{execution.node_id} not found for execution #{execution.id}")

              update_command_execution(execution, %{
                status: "completed",
                exit_code: -1,
                output: "Node not found"
              })

              :error
          end

        node ->
          node
      end

    case node do
      :error ->
        :error

      _ ->
        # Get the command to access command_text
        command = get_command!(execution.command_id)

        execution_data = %{
          id: execution.id,
          command_id: execution.command_id,
          node_id: execution.node_id,
          command_text: command.command_text,
          status: "pending"
        }

        try do
          case send_command_to_node(node.vpn_ip, execution_data) do
            {:ok, _response} ->
              update_command_execution(execution, %{
                status: "sent",
                sent_at: DateTime.utc_now()
              })

              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to send execution #{execution.id} to node #{node.vpn_ip}: #{inspect(reason)}"
              )

              :error
          end
        rescue
          exception ->
            Logger.error("Exception in send_command_to_node: #{inspect(exception)}")
            :error
        end
    end
  end

  @doc """
  HTTP client to send command execution to a node.

  This is the abstraction layer that can be swapped to Erlang distribution later.
  """
  def send_command_to_node(node_vpn_ip, execution_data) do
    url = "http://#{node_vpn_ip}:4000/api/command_executions"

    case Req.post(url, json: execution_data, receive_timeout: 5000) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :sent}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retries pending command executions in FIFO order per node.

  Used by ExecutionRetryWorker cron job.
  """
  def retry_pending_executions do
    Logger.info("Starting retry of pending executions")

    # Get all pending executions grouped by node_id, ordered by creation time
    pending_executions =
      from(ce in CommandExecution,
        where: ce.status == "pending",
        order_by: [asc: ce.node_id, asc: ce.inserted_at]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.node_id)

    # Process oldest pending execution for each node
    Enum.each(pending_executions, fn {_node_id, executions} ->
      # Take only the oldest execution for this node
      oldest_execution = List.first(executions)
      attempt_execution_delivery(oldest_execution)
    end)

    Logger.info("Completed retry of pending executions")
    :ok
  end
end
