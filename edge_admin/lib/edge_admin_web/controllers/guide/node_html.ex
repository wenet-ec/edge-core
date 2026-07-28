# edge_admin/lib/edge_admin_web/controllers/guide/node_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.NodeHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("node_html/*")
end
