# edge_admin/lib/edge_admin_web/controllers/guide/event_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.EventHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("event_html/*")
end
