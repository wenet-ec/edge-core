# edge_admin/lib/edge_admin_web/controllers/guide/metrics_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.MetricsHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("metrics_html/*")
end
