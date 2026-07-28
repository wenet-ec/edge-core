# edge_admin/lib/edge_admin_web/controllers/guide/ssh_html.ex
defmodule EdgeAdminWeb.Controllers.Guide.SshHTML do
  @moduledoc false

  use EdgeAdminWeb, :html

  import EdgeAdminWeb.Controllers.Guide.Layout

  embed_templates("ssh_html/*")
end
