# edge_admin/lib/edge_admin/commands/resources/command_executions.ex
defmodule EdgeAdmin.Commands.Resources.CommandExecutions do
  @moduledoc "Command-execution persistence and filtering operations."

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Commands.Checks.CommandExecutionTerminalCheck
  alias EdgeAdmin.Commands.Filters.CommandExecutionFilters
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser

  @doc "Gets a command execution by ID with its command preloaded."
  @spec get(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, Repo.preload(execution, :command)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Creates a command execution."
  @spec create(map()) :: {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs \\ %{}) do
    %CommandExecution{} |> CommandExecution.changeset(attrs) |> Repo.insert()
  end

  @doc "Updates a command execution."
  @spec update(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def update(%CommandExecution{} = execution, attrs) do
    execution |> CommandExecution.changeset(attrs) |> Repo.update()
  end

  @doc "Deletes a command execution when it is terminal."
  @spec delete(CommandExecution.t()) ::
          {:ok, CommandExecution.t()} | {:error, {:conflict, String.t()}}
  def delete(%CommandExecution{} = execution) do
    with :ok <- CommandExecutionTerminalCheck.check(execution), do: Repo.delete(execution)
  end

  @doc "Builds a command-execution changeset."
  @spec change(CommandExecution.t(), map()) :: Ecto.Changeset.t()
  def change(%CommandExecution{} = execution, attrs \\ %{}), do: CommandExecution.changeset(execution, attrs)

  @doc "Lists command executions with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[CommandExecution.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = RequestParser.parse(params)
    {custom, ilike_filters, flop_params} = split_filters(flop_params)

    query =
      from(ce in CommandExecution,
        left_join: n in assoc(ce, :node),
        left_join: c in assoc(n, :cluster),
        preload: [:command, :cluster, node: :cluster]
      )
      |> CommandExecutionFilters.apply_command_ids(custom.command_id)
      |> CommandExecutionFilters.apply_cluster_name(custom.cluster_name)
      |> CommandExecutionFilters.apply_node_ids(custom.node_id)
      |> CommandExecutionFilters.apply_has_cluster(custom.has_cluster)
      |> CommandExecutionFilters.apply_has_output(custom.has_output)

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(ce in acc, where: case_insensitive_like(field(ce, ^field), ^value))
      end)

    Flop.validate_and_run(query, flop_params, for: CommandExecution, replace_invalid_params: true)
  end

  defp split_filters(flop_params) do
    custom_fields = [:command_id, :cluster_name, :node_id, :has_cluster, :has_output]

    {custom_filters, rest} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field in custom_fields))

    custom = Map.new(custom_fields, fn field -> {field, Enum.filter(custom_filters, &(&1.field == field))} end)
    {ilike_filters, flop_params} = RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:output])
    {custom, ilike_filters, flop_params}
  end
end
