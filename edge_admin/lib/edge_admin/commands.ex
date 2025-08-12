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
    TargetAllDispatchWorker,
    TargetNodesDispatchWorker
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
    case create_command(attrs) do
      {:ok, command} ->
        dispatch_executions_with_targeting(command, attrs)
        {:ok, command}

      {:error, changeset} ->
        Logger.error("Failed to create command: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp dispatch_executions_with_targeting(command, %{"targeting" => targeting}) do
    case targeting["type"] do
      "all" ->
        %{
          command_id: command.id,
          node_filters: Map.get(targeting, "node_filters", %{})
        }
        |> TargetAllDispatchWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to enqueue TargetAllDispatchWorker: #{inspect(reason)}")
        end

      "nodes" ->
        %{
          command_id: command.id,
          node_ids: Map.get(targeting, "ids", []),
          node_filters: Map.get(targeting, "node_filters", %{})
        }
        |> TargetNodesDispatchWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to enqueue TargetNodesDispatchWorker: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("Invalid targeting type for command #{command.id}: #{inspect(targeting)}")
        :ok
    end
  end

  defp dispatch_executions_with_targeting(command, attrs) do
    Logger.warning(
      "No targeting specification found for command #{command.id}, attrs: #{inspect(attrs)}"
    )

    :ok
  end

  def create_executions_for_target_all(command_id, node_filters \\ %{}) do
    command = get_command!(command_id)

    # Get all nodes by handling pagination
    nodes = get_all_filtered_nodes(node_filters)

    Logger.info("Creating executions for #{length(nodes)} filtered nodes")

    # Truncate to match PostgreSQL precision
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    executions =
      Enum.map(nodes, fn node ->
        %{
          command_id: command_id,
          node_id: node.id,
          target_all: true,
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, inserted_executions} =
        Repo.insert_all(CommandExecution, executions, returning: true)

      Logger.info("Successfully created #{count} command executions")

      executions_with_command_text =
        Enum.map(inserted_executions, fn execution ->
          %CommandExecution{execution | command_text: command.command_text}
        end)

      {:ok, executions_with_command_text}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  def create_executions_for_target_nodes(command_id, node_ids, node_filters \\ %{}) do
    command = get_command!(command_id)
    unique_node_ids = Enum.uniq(node_ids)

    # Get the specified nodes
    specified_nodes = Nodes.get_nodes_by_ids(unique_node_ids)

    nodes =
      specified_nodes
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, node} -> node end)

    # Apply node_filters if any are provided
    filtered_nodes =
      if Enum.empty?(node_filters) do
        nodes
      else
        # Use the same helper function to get all matching nodes
        all_matching_nodes = get_all_filtered_nodes(node_filters)
        matching_node_ids = MapSet.new(all_matching_nodes, & &1.id)
        Enum.filter(nodes, fn node -> MapSet.member?(matching_node_ids, node.id) end)
      end

    Logger.info(
      "Creating executions for #{length(filtered_nodes)} nodes (#{length(nodes)} specified, #{length(filtered_nodes)} after filtering)"
    )

    results =
      Enum.map(filtered_nodes, fn node ->
        execution_attrs = %{
          command_id: command_id,
          node_id: node.id,
          target_all: false,
          status: "pending",
          command_text: command.command_text
        }

        case create_command_execution(execution_attrs) do
          {:ok, execution} ->
            execution = %{execution | command_text: command.command_text}

            pending_count = count_pending_executions_for_node(node.id)

            if pending_count > 1 do
              {:ok, execution}
            else
              # No other pending executions, attempt immediate delivery
              case attempt_execution_delivery(execution, node) do
                :ok ->
                  {:ok, execution}

                :error ->
                  {:ok, execution}
              end
            end

          {:error, changeset} ->
            Logger.error(
              "Failed to create execution for node #{node.id}: #{inspect(changeset.errors)}"
            )

            {:error, changeset}
        end
      end)

    {successes, errors} = Enum.split_with(results, &match?({:ok, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(successes, fn {:ok, execution} -> execution end)}
    else
      {:partial_success, %{successes: successes, errors: errors}}
    end
  end

  defp count_pending_executions_for_node(node_id) do
    from(ce in CommandExecution,
      where: ce.node_id == ^node_id and ce.status == "pending",
      select: count(ce.id)
    )
    |> Repo.one()
  end

  # Helper function to get all nodes across all pages
  defp get_all_filtered_nodes(node_filters, page \\ 1, accumulated_nodes \\ []) do
    params =
      node_filters
      # Reasonable page size
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    page_result = Nodes.list_nodes_with_filtering_pagination(params)

    all_nodes = accumulated_nodes ++ page_result.data

    if page_result.has_next do
      get_all_filtered_nodes(node_filters, page + 1, all_nodes)
    else
      all_nodes
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
      |> Repo.preload(:command)
      |> Enum.map(&CommandExecution.populate_command_text/1)
      |> Enum.group_by(& &1.node_id)

    # Process ALL pending executions for each node in bulk
    Enum.each(pending_executions, fn {node_id, executions} ->
      # Send all executions for this node in order
      Enum.each(executions, fn execution ->
        attempt_execution_delivery(execution)
      end)
    end)

    Logger.info("Completed retry of pending executions")
    :ok
  end
end
