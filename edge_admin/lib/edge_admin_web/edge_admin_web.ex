# edge_admin/lib/edge_admin_web/edge_admin_web.ex
defmodule EdgeAdminWeb do
  @moduledoc """
  Shared web-layer macros for controllers, HTML components, channels, routes,
  and OpenAPI-aware API controllers.
  """

  # Only files actually present in priv/static — narrowing this list shrinks
  # the gzip cache and avoids advertising paths that 404.
  @doc "Returns the static asset paths exposed by the Admin endpoint."
  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        # Pure API — no HTML layouts.
        formats: [:json],
        layouts: []

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc """
  HTML-only controller surface for the small number of browser pages that
  belong to Edge Admin itself. API controllers intentionally remain JSON-only.
  """
  def html_controller do
    quote do
      use Phoenix.Controller,
        formats: [:html],
        layouts: []

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      unquote(verified_routes())
    end
  end

  @doc """
  Like `:controller`, but with `OpenApiSpex.Plug.CastAndValidate` already
  installed against `EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer`.

  Use this for any controller whose actions are documented in the OpenAPI
  spec. Use plain `:controller` for special cases that don't validate (the
  fallback controller, OpenAPI/AsyncAPI spec serving, etc.).
  """
  def api_controller do
    quote do
      unquote(controller())

      plug OpenApiSpex.Plug.CastAndValidate,
        render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: EdgeAdminWeb.Endpoint,
        router: EdgeAdminWeb.Router,
        statics: EdgeAdminWeb.static_paths()
    end
  end

  @doc """
  Dispatches to the requested web-layer macro.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
