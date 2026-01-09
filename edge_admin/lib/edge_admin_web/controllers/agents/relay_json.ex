# edge_admin_web/controllers/agents/relay_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.RelayJSON do
  @moduledoc """
  Renders relay registration responses.
  """

  @doc """
  Renders relay registration success with admin name.
  """
  def create(%{relay_admin_name: relay_admin_name}) do
    %{data: %{relay_admin_name: relay_admin_name}}
  end
end
