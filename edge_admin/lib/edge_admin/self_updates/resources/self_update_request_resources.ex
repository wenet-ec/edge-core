# edge_admin/lib/edge_admin/self_updates/resources/self_update_request_resources.ex
defmodule EdgeAdmin.SelfUpdates.Resources.SelfUpdateRequestResources do
  @moduledoc """
  Persistence and request-level operations for self-update requests.

  Creation validates and inserts the request before attempting to queue
  asynchronous processing. A queue insertion failure is logged without
  undoing the request. Deletion is allowed only after processing completes.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.SelfUpdates.Checks.RequestCompletedCheck
  alias EdgeAdmin.SelfUpdates.Forms.CreateSelfUpdateRequestForm
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Workers.TriggerSelfUpdateWorker

  require Logger

  @spec list(map()) :: {:ok, {[SelfUpdateRequest.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    Flop.validate_and_run(SelfUpdateRequest, EdgeAdmin.RequestParser.parse(params),
      for: SelfUpdateRequest,
      replace_invalid_params: true
    )
  end

  @spec get(String.t()) :: {:ok, SelfUpdateRequest.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(SelfUpdateRequest, id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @spec create(map()) :: {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs), do: %SelfUpdateRequest{} |> SelfUpdateRequest.changeset(attrs) |> Repo.insert()

  @spec update(SelfUpdateRequest.t(), map()) :: {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def update(%SelfUpdateRequest{} = request, attrs), do: request |> SelfUpdateRequest.changeset(attrs) |> Repo.update()

  @spec delete(SelfUpdateRequest.t()) :: {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def delete(%SelfUpdateRequest{} = request), do: Repo.delete(request)

  @doc "Validates and inserts a request, then attempts to queue asynchronous processing."
  @spec create_and_enqueue_processing_job(map()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def create_and_enqueue_processing_job(attrs \\ %{}) do
    with {:ok, attrs} <- CreateSelfUpdateRequestForm.changeset(attrs),
         {:ok, request} <- create(attrs) do
      enqueue_processing_job(request.id)
      {:ok, request}
    end
  end

  @doc "Returns whether the latest self-update request targets a node and when it was created."
  @spec latest_for_node(Node.t(), (map() -> [Node.t()])) ::
          {:ok, %{including_me: boolean(), inserted_at: DateTime.t() | nil}}
  def latest_for_node(node, resolve_targeting) do
    request = SelfUpdateRequest |> order_by([r], desc: r.inserted_at) |> limit(1) |> Repo.one()

    case request do
      nil ->
        {:ok, %{including_me: false, inserted_at: nil}}

      request ->
        {:ok,
         %{
           including_me: Enum.any?(resolve_targeting.(request.targeting), &(&1.id == node.id)),
           inserted_at: request.inserted_at
         }}
    end
  end

  @doc "Deletes a self-update request only after its processing has completed."
  @spec delete_if_completed(SelfUpdateRequest.t()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, {:conflict, String.t()} | Ecto.Changeset.t()}
  def delete_if_completed(%SelfUpdateRequest{} = request) do
    with :ok <- RequestCompletedCheck.check(request), do: delete(request)
  end

  defp enqueue_processing_job(request_id) do
    case %{request_id: request_id} |> TriggerSelfUpdateWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue self-update request processing for #{request_id}: #{inspect(reason)}")
    end
  end
end
