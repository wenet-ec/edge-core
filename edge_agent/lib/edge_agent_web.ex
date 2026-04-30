# edge_agent/lib/edge_agent_web.ex
defmodule EdgeAgentWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use EdgeAgentWeb, :controller
      use EdgeAgentWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # Only files actually present in priv/static.
  def static_paths, do: ~w(favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller

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
    end
  end

  # Verified routes — used by ConnCase tests for `~p"/..."` route construction.
  # Not imported into controllers because no controller currently builds URLs;
  # if that changes, add `unquote(verified_routes())` to `controller/0`.
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: EdgeAgentWeb.Endpoint,
        router: EdgeAgentWeb.Router,
        statics: EdgeAgentWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
