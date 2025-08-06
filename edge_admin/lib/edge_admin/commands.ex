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

  def get_command!(id), do: Repo.get!(Command, id)

  def create_command(attrs \\ %{}) do
    %Command{}
    |> Command.changeset(attrs)
    |> Repo.insert()
  end

  def update_command(%Command{} = command, attrs) do
    command
    |> Command.changeset(attrs)
    |> Repo.update()
  end

  def delete_command(%Command{} = command) do
    Repo.delete(command)
  end

  def change_command(%Command{} = command, attrs \\ %{}) do
    Command.changeset(command, attrs)
  end

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

  defp preload_and_populate_command_text(execution_or_executions) do
    case execution_or_executions do
      # Handle single execution
      %CommandExecution{} = execution ->
        execution
        |> Repo.preload(:command)
        |> CommandExecution.populate_command_text()

      # Handle list of executions
      executions when is_list(executions) ->
        executions
        |> Repo.preload(:command)
        |> Enum.map(&CommandExecution.populate_command_text/1)

      # Handle other cases (shouldn't happen but defensive)
      other ->
        other
    end
  end

  def get_command_execution!(id) do
    CommandExecution
    |> Repo.get!(id)
    |> preload_and_populate_command_text()
  end

  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  def list_command_executions_with_filtering_pagination(params \\ %{}) do
    page_result =
      FilteringPagination.paginate(
        CommandExecution,
        params,
        filterable_fields: [:status, :target_all, :exit_code, :command_id, :node_id, :output],
        sortable_fields: [:inserted_at, :updated_at, :status, :sent_at, :completed_at, :exit_code],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    executions_with_command_text =
      page_result.data
      |> Repo.preload(:command)
      |> Enum.map(&CommandExecution.populate_command_text/1)

    %{page_result | data: executions_with_command_text}
  end

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

  def create_executions_for_all_nodes(command_id) do
    # Get the command for command_text
    command = get_command!(command_id)

    # Get all nodes
    page_result = Nodes.list_nodes_with_filtering_pagination(%{"page_size" => "1000"})

    # Create executions with command_text directly in the struct
    executions =
      Enum.map(page_result.data, fn node ->
        %CommandExecution{}
        |> CommandExecution.changeset(%{
          command_id: command_id,
          node_id: node.id,
          target_all: true,
          status: "pending"
        })
        |> Repo.insert!()
      end)

    # Bulk insert
    try do
      {count, executions} = Repo.insert_all(CommandExecution, executions, returning: true)
      Logger.info("Successfully created #{count} command executions")

      # Return executions with command_text populated
      executions_with_command_text =
        Enum.map(executions, fn execution ->
          %CommandExecution{execution | command_text: command.command_text}
        end)

      {:ok, executions_with_command_text}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  def create_executions_for_target_nodes(command_id, node_ids) do
    # Get the command for command_text
    command = get_command!(command_id)

    # Deduplicate node IDs
    unique_node_ids = Enum.uniq(node_ids)

    # Get nodes
    nodes = Nodes.get_nodes_by_ids(unique_node_ids)

    results =
      Enum.map(nodes, fn
        {:ok, node} ->
          # Create execution with command_text in attrs
          execution_attrs = %{
            command_id: command_id,
            node_id: node.id,
            target_all: false,
            status: "pending",
            # Set virtual field
            command_text: command.command_text
          }

          case create_command_execution(execution_attrs) do
            {:ok, execution} ->
              # Populate command_text since it's virtual
              execution = %{execution | command_text: command.command_text}

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

  def attempt_execution_delivery(execution, node \\ nil) do
    # Get node info if not provided
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
        # Use command_text from virtual field
        execution_data = %{
          id: execution.id,
          command_id: execution.command_id,
          node_id: execution.node_id,
          command_text: execution.command_text,
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

  def retry_pending_executions do
    Logger.info("Starting retry of pending executions")

    # Get all pending executions grouped by node_id, ordered by creation time
    pending_executions =
      from(ce in CommandExecution,
        where: ce.status == "pending",
        order_by: [asc: ce.node_id, asc: ce.inserted_at]
      )
      |> Repo.all()
      # Add preload
      |> Repo.preload(:command)
      # Populate virtual field
      |> Enum.map(&CommandExecution.populate_command_text/1)
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
