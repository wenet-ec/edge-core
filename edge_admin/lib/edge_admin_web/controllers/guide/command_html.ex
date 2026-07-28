# edge_admin/lib/edge_admin_web/controllers/guide/command_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.CommandHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("command_html/*")
end
