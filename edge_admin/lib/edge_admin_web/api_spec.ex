# lib/edge_admin_web/api_spec.ex
defmodule EdgeAdminWeb.ApiSpec do
  @moduledoc false
  @behaviour OpenApiSpex.OpenApi

  alias EdgeAdminWeb.Router
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.Server

  @impl OpenApi
  def spec do
    OpenApiSpex.resolve_schema_modules(%OpenApi{
      servers: [%Server{url: "http://localhost:4000"}],
      info: %Info{
        title: "EdgeAdmin API",
        version: "0.0.1",
        description: """
        EdgeAdmin API - A backend REST API that serves as a wrapper for various systems.
        This API is designed for internal network use only and provides administrative
        functionality for edge computing systems.
        """
      },
      paths: Paths.from_router(Router)
    })

    # Populate the paths from the phoenix router

    # Discover request/response schemas from path specs
  end
end
