# edge_admin/lib/edge_admin/self_updates/self_updates.ex
defmodule EdgeAdmin.SelfUpdates do
  @moduledoc """
  Canonical API for self-update requests.

  Persistence is implemented by `Resources.Requests`; delivery processing is
  implemented by `Workflows.Processing`.
  """

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.SelfUpdates.Checks
  alias EdgeAdmin.SelfUpdates.Resources.Requests
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Workflows.Processing

  @doc "Gets a self-update request by ID."
  @spec get_self_update_request(String.t()) :: {:ok, SelfUpdateRequest.t()} | {:error, :not_found}
  defdelegate get_self_update_request(id), to: Requests, as: :get

  @doc "Creates a self-update request and queues its processing worker."
  @spec create_self_update_request(map()) :: {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_self_update_request(attrs \\ %{}), to: Requests, as: :create

  @doc "Updates a self-update request."
  @spec update_self_update_request(SelfUpdateRequest.t(), map()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_self_update_request(request, attrs), to: Requests, as: :update

  @doc "Lists self-update requests with filtering, sorting, and pagination."
  @spec list_self_update_requests(map()) ::
          {:ok, {[SelfUpdateRequest.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_self_update_requests(params \\ %{}), to: Requests, as: :list

  @doc "Processes a self-update request and records its delivery summary."
  @spec process_self_update_request(String.t()) :: :ok
  defdelegate process_self_update_request(request_id), to: Processing

  @spec check_for_latest_request(Node.t()) ::
          {:ok, %{including_me: boolean(), inserted_at: DateTime.t() | nil}}
  def check_for_latest_request(%Node{} = node),
    do: Requests.latest_for_node(node, &Processing.resolve_targeting_and_filter/1)

  @spec delete_self_update_request(SelfUpdateRequest.t()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, {:conflict, String.t()}}
  def delete_self_update_request(%SelfUpdateRequest{} = request) do
    with :ok <- Checks.RequestCompletedCheck.check(request), do: Requests.delete(request)
  end
end
