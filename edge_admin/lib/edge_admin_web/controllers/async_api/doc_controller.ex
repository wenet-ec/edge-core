# edge_admin/lib/edge_admin_web/controllers/asyncapi/doc_controller.ex
defmodule EdgeAdminWeb.Controllers.AsyncApi.DocController do
  @moduledoc false

  use EdgeAdminWeb, :controller

  @asyncapi_component_version "3.1.0"
  @asyncapi_css_cdn "https://unpkg.com/@asyncapi/react-component@#{@asyncapi_component_version}/styles/default.min.css"
  @asyncapi_js_cdn "https://unpkg.com/@asyncapi/react-component@#{@asyncapi_component_version}/browser/standalone/index.js"

  # Built entirely from compile-time constants — no runtime interpolation.
  @html """
  <!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Edge Admin — AsyncAPI Docs</title>
      <link rel="stylesheet" href="#{@asyncapi_css_cdn}" />
      <script src="#{@asyncapi_js_cdn}"></script>
      <style>
        html, body { margin: 0; padding: 0; height: 100%; background: #fff; }
        #asyncapi { height: 100vh; }
        #loading {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100vh;
          gap: 16px;
          font-family: sans-serif;
          color: #666;
          font-size: 14px;
        }
        .spinner {
          width: 36px;
          height: 36px;
          border: 3px solid #e0e0e0;
          border-top-color: #47a0e5;
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
      </style>
    </head>
    <body>
      <div id="loading">
        <div class="spinner"></div>
        <span>Loading AsyncAPI docs…</span>
      </div>
      <div id="asyncapi" style="display:none"></div>
      <script>
        const container = document.getElementById('asyncapi');
        const loading = document.getElementById('loading');

        // AsyncApiStandalone.render() fetches /api/asyncapi asynchronously — there
        // is no callback or promise. Use a MutationObserver to detect when the
        // component actually inserts content into the container, then swap visibility.
        const observer = new MutationObserver(() => {
          if (container.children.length > 0) {
            observer.disconnect();
            loading.style.display = 'none';
            container.style.display = 'block';
          }
        });
        observer.observe(container, { childList: true, subtree: false });

        AsyncApiStandalone.render(
          {
            schema: { url: '/api/asyncapi' },
            config: {
              show: {
                sidebar: true,
                info: true,
                servers: true,
                operations: true,
                messages: true,
                schemas: true,
                errors: true,
              },
            },
          },
          container
        );
      </script>
    </body>
  </html>
  """

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, @html)
  end
end
