# edge_admin/lib/edge_admin_web/edge_admin_web.ex
defmodule EdgeAdminWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use EdgeAdminWeb, :controller
      use EdgeAdminWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # Only files actually present in priv/static — narrowing this list shrinks
  # the gzip cache and avoids advertising paths that 404.
  def static_paths, do: ~w(assets favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Phoenix.LiveView.Router

      # Import common connection and controller functions to use in pipelines
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
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
