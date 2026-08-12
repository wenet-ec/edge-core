# edge_agent/lib/edge_agent_web/edge_agent_web.ex
defmodule EdgeAgentWeb do
  @moduledoc """
  Shared Phoenix imports, aliases, and route helpers for the Agent web layer.
  """

  @spec static_paths() :: [String.t()]
  def static_paths, do: ~w(favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
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
        formats: [:json],
        layouts: []

      import Plug.Conn
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: EdgeAgentWeb.Endpoint,
        router: EdgeAgentWeb.Router,
        statics: EdgeAgentWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
