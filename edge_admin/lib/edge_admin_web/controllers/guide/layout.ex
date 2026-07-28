# edge_admin/lib/edge_admin_web/controllers/guide/layout.ex
defmodule EdgeAdminWeb.Controllers.Guide.Layout do
  @moduledoc false

  use EdgeAdminWeb, :html

  attr :title, :string, required: true
  attr :description, :string, required: true
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="description" content={@description} />
        <title>{@title} — Edge Admin guide</title>
        <link rel="stylesheet" href="/assets/guide.css" />
      </head>
      <body>
        <main class="guide">
          <header class="guide-header">
            <a class="wordmark" href="/">Edge Admin</a>
            <nav aria-label="Documentation">
              <a href="/swaggerui">Swagger UI</a>
              <a href="/redoc">Reference</a>
              <a href="/asyncdoc">Events</a>
            </nav>
          </header>

          <%= render_slot(@inner_block) %>

          <footer>
            <span>Edge Admin documentation</span>
            <nav aria-label="More Edge Admin resources">
              <a href="https://wenet-ec.github.io/edge-core/">Full documentation</a>
              <a href="https://github.com/wenet-ec/edge-core">Source on GitHub</a>
            </nav>
          </footer>
        </main>
      </body>
    </html>
    """
  end
end
