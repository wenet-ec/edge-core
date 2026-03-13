# edge_admin/lib/edge_admin_web/schema.ex
defmodule EdgeAdminWeb.Schema do
  @moduledoc """
  Convenience wrapper around `OpenApiSpex.schema/2`.

  All web-layer OpenAPI schema modules are pure documentation — they are never
  used as Elixir structs or serialised directly via Jason. Using the raw
  `OpenApiSpex.schema/2` macro with default options causes dialyzer false
  positives because it generates `@derive Jason.Encoder` through a
  `Code.ensure_loaded?` runtime check that dialyzer cannot trace.

  `use EdgeAdminWeb.Schema` in any schema module to get:
    - `require OpenApiSpex` (so the macro is available)
    - a local `schema/1` macro that always passes `struct?: false, derive?: false`
  """

  defmacro __using__(_opts) do
    quote do
      import EdgeAdminWeb.Schema, only: [schema: 1]

      require OpenApiSpex
    end
  end

  @doc """
  Defines an OpenAPI schema without generating a struct or Jason.Encoder derivation.

  Delegates to `OpenApiSpex.schema/2` with `struct?: false, derive?: false`.
  """
  defmacro schema(body) do
    quote do
      OpenApiSpex.schema(unquote(body), struct?: false, derive?: false)
    end
  end
end
