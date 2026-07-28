# edge_admin/lib/edge_admin_web/controllers/guide/proxy_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.ProxyHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("proxy_html/*")
end
