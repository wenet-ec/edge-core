# edge_admin/lib/edge_admin/self_updates/resources/requests.ex
defmodule EdgeAdmin.SelfUpdates.Resources.Requests do
  @moduledoc "Persistence and queries for self-update requests."

  import Ecto.Query, warn: false

  alias EdgeAdmin.Repo
  alias EdgeAdmin.SelfUpdates.Forms
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Workers.TriggerSelfUpdateWorker

  def get(id) do
    case Repo.get(SelfUpdateRequest, id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def create(attrs \\ %{}) do
    with {:ok, attrs} <- Forms.CreateSelfUpdateRequestForm.changeset(attrs),
         {:ok, request} <- Repo.insert(SelfUpdateRequest.changeset(%SelfUpdateRequest{}, attrs)) do
      %{request_id: request.id} |> TriggerSelfUpdateWorker.new() |> Oban.insert()
      {:ok, request}
    end
  end

  def update(%SelfUpdateRequest{} = request, attrs), do: request |> SelfUpdateRequest.changeset(attrs) |> Repo.update()

  def list(params \\ %{}) do
    Flop.validate_and_run(SelfUpdateRequest, EdgeAdmin.RequestParser.parse(params),
      for: SelfUpdateRequest,
      replace_invalid_params: true
    )
  end

  def latest_for_node(node, resolve_fun) do
    request = SelfUpdateRequest |> order_by([r], desc: r.inserted_at) |> limit(1) |> Repo.one()

    case request do
      nil ->
        {:ok, %{including_me: false, inserted_at: nil}}

      request ->
        {:ok,
         %{
           including_me: Enum.any?(resolve_fun.(request.targeting), &(&1.id == node.id)),
           inserted_at: request.inserted_at
         }}
    end
  end

  def delete(%SelfUpdateRequest{} = request), do: Repo.delete(request)
end
