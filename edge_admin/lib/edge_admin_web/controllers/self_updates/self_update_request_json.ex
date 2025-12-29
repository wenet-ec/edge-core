# edge_admin_web/controllers/self_updates/self_update_request_json.ex
defmodule EdgeAdminWeb.Controllers.SelfUpdates.SelfUpdateRequestJSON do
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  @doc """
  Renders a paginated list of self-update requests.
  """
  def index(%{requests: requests, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(request <- requests, do: data(request)),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  @doc """
  Renders a single self-update request.
  """
  def show(%{request: request}) do
    %{data: data(request)}
  end

  defp data(%SelfUpdateRequest{} = request) do
    %{
      id: request.id,
      targeting: request.targeting,
      status: request.status,
      summary: request.summary,
      inserted_at: request.inserted_at,
      updated_at: request.updated_at
    }
  end
end
