# edge_admin/lib/edge_admin_web/schemas/common_schemas.ex
defmodule EdgeAdminWeb.Schemas.CommonSchemas do
  @moduledoc """
  Common OpenAPI schemas shared across the application
  """

  alias OpenApiSpex.Schema

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error Response",
      description: "Standard error response for validation and other errors",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          description: "Error details with field-specific messages",
          additionalProperties: %Schema{
            type: :array,
            items: %Schema{type: :string}
          }
        }
      },
      required: [:errors],
      example: %{
        errors: %{
          id: ["can't be blank", "has already been taken"]
        }
      }
    })
  end

  defmodule NotFoundResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Not Found Response",
      description: "Resource not found error",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          description: "Error message"
        }
      },
      required: [:error],
      example: %{
        error: "Resource not found"
      }
    })
  end

  defmodule GenericErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Generic Error Response",
      description: "Generic error response for various error conditions",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          description: "Error message"
        },
        message: %Schema{
          type: :string,
          description: "Additional details (optional)"
        },
        details: %Schema{
          type: :string,
          description: "Technical details (optional)"
        }
      },
      required: [:error],
      example: %{
        error: "Operation failed",
        message: "Additional context about the error",
        details: "Technical details for debugging"
      }
    })
  end
end
