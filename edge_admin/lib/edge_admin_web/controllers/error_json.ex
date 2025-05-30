# lib/edge_admin_web/controllers/error_json.ex
defmodule EdgeAdminWeb.ErrorJSON do
  @moduledoc """
  This module handles JSON error responses for the API.
  """

  # Keep your existing error handling, but you could now use
  # verified routes if you need to reference routes in error responses

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
