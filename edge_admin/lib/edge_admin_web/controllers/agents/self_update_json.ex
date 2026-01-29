# edge_admin_web/controllers/agents/self_update_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SelfUpdateJson do
  @moduledoc """
  JSON rendering for agent self-update endpoints.
  """

  @doc """
  Renders the result of checking for the latest self-update request.
  """
  def check(%{result: result}) do
    %{
      data: %{
        including_me: result.including_me,
        inserted_at: result.inserted_at
      }
    }
  end
end
