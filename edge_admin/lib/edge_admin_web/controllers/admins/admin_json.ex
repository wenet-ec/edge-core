# edge_admin/lib/edge_admin_web/controllers/admins/admin_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminJSON do
  @moduledoc """
  JSON rendering for admin identity.
  """

  @doc """
  Renders this admin's identity.
  """
  def show(%{admin: admin}) do
    %{data: admin}
  end
end
