# edge_admin/lib/edge_admin/commands/resources/command_resources.ex
defmodule EdgeAdmin.Commands.Resources.CommandResources do
  @moduledoc false

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Commands.Checks.PendingCommandExecutionsCheck
  alias EdgeAdmin.Commands.Filters.CommandFilters
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser

  @spec get(String.t()) :: {:ok, Command.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Command, id) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Lists commands with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[Command.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = RequestParser.parse(params)

    {has_timeout_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field == :has_timeout))

    {has_expires_at_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :has_expires_at))

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(Map.put(flop_params, :filters, other_filters), [:command_text])

    base_query =
      Enum.reduce(ilike_filters, Command, fn %{field: field, value: value}, acc ->
        from(c in acc, where: case_insensitive_like(field(c, ^field), ^value))
      end)

    query =
      base_query
      |> CommandFilters.apply_has_timeout(has_timeout_filters)
      |> CommandFilters.apply_has_expires_at(has_expires_at_filters)

    Flop.validate_and_run(query, flop_params, for: Command, replace_invalid_params: true)
  end

  @spec create(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: %Command{} |> Command.changeset(attrs) |> Repo.insert()

  @spec delete(Command.t()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Command{} = command), do: Repo.delete(command)

  @doc "Deletes a command only when none of its executions are in flight."
  @spec delete_if_no_in_flight_executions(Command.t()) ::
          {:ok, Command.t()} | {:error, {:conflict, String.t()} | Ecto.Changeset.t()}
  def delete_if_no_in_flight_executions(%Command{} = command) do
    with :ok <- PendingCommandExecutionsCheck.check(command), do: delete(command)
  end
end
