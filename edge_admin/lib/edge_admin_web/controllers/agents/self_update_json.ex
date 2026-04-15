# edge_admin_web/controllers/agents/self_update_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SelfUpdateJson do
  @moduledoc false
  alias EdgeAdminWeb.ResponseEnvelope

  def check(%{conn: conn, result: result}) do
    ResponseEnvelope.success(conn, %{
      including_me: result.including_me,
      inserted_at: result.inserted_at
    })
  end
end
