# edge_admin/lib/edge_admin_web/controllers/async_api/doc_controller.ex
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
        /* Edge Core navy palette — lighter end so headings don't read black.
         * AsyncAPI's default teal/green operation pills are intentionally
         * kept as-is; we only retint the bright blue links + sidebar. */
        :root {
          --ec-navy-800: #24344d;
          --ec-navy-700: #2e4263;
          --ec-navy-600: #3e567c;
          --ec-navy-500: #506d96;
        }

        html, body { margin: 0; padding: 0; height: 100%; background: #fff; }
        #asyncapi { height: 100vh; }
        #loading {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100vh;
          gap: 16px;
          font-family: Inter, ui-sans-serif, system-ui, sans-serif;
          color: var(--ec-navy-500);
          font-size: 14px;
        }
        .spinner {
          width: 36px;
          height: 36px;
          border: 3px solid #e0e0e0;
          border-top-color: var(--ec-navy-600);
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* ---- AsyncAPI React component overrides (light-touch) ----
         * Recolour the bright Tailwind blue used in links + section
         * accents to a softer navy. Leave operation pills (teal/green)
         * alone — those are pub/sub semantic colors developers expect.
         */
        #asyncapi a { color: var(--ec-navy-600); }
        #asyncapi a:hover { color: var(--ec-navy-700); }

        #asyncapi h1,
        #asyncapi h2,
        #asyncapi h3,
        #asyncapi h4 { color: var(--ec-navy-600); }

        #asyncapi .sidebar {
          background: #fafbfc;
          border-right: 1px solid #e1e5eb;
        }

        /* Knock the bright Tailwind blue down to navy where it appears
         * as a generic section accent (not a semantic operation color). */
        #asyncapi .text-blue-500,
        #asyncapi .text-blue-600,
        #asyncapi .text-blue-700 { color: var(--ec-navy-600) !important; }
        #asyncapi .border-blue-500,
        #asyncapi .border-blue-600 { border-color: var(--ec-navy-600) !important; }

        /* "Examples" / "Payload" labels render inside a dark navy panel —
         * the upstream light-blue is unreadable on that background. Force
         * them white so they're legible against the panel. */
        #asyncapi .examples,
        #asyncapi .payload,
        #asyncapi .panel-item--right .text-blue-500,
        #asyncapi .panel-item--right .text-blue-600,
        #asyncapi .panel-item--right .text-blue-700,
        #asyncapi .panel-item--right h2,
        #asyncapi .panel-item--right h3,
        #asyncapi .panel-item--right h4 { color: #ffffff !important; }

        /* Markdown code blocks in the document body (Info description,
         * Servers descriptions, Channel descriptions) inherit highlight.js's
         * night-owl theme — almost-black, jarring against the light document
         * body. Lift them to navy-600 so they still read as "code surface"
         * but in our brand palette instead of pitch black. Right panel
         * code blocks are left alone (they sit in an already-dark panel). */
        #asyncapi .panel-item--center pre,
        #asyncapi .panel-item--center pre code,
        #asyncapi .panel-item--center pre code.hljs,
        #asyncapi .panel-item--center .prose pre,
        #asyncapi .panel-item--center .prose pre code {
          background: var(--ec-navy-800) !important;
          color: #ffffff !important;
        }
        #asyncapi .panel-item--center pre code .hljs-string,
        #asyncapi .panel-item--center pre code .hljs-attr { color: #e0bf6e !important; }
        #asyncapi .panel-item--center pre code .hljs-number,
        #asyncapi .panel-item--center pre code .hljs-literal { color: #c9942e !important; }
        #asyncapi .panel-item--center pre code .hljs-comment { color: rgba(255, 255, 255, 0.6) !important; font-style: italic; }
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
