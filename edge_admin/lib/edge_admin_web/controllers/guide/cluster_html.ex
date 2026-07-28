# edge_admin/lib/edge_admin_web/controllers/guide/cluster_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.ClusterHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("cluster_html/*")
end
