# edge_admin/lib/edge_admin_web/controllers/guide/index_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.IndexHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("index_html/*")
end
