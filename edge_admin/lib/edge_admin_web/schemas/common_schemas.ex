# edge_admin/lib/edge_admin_web/schemas/common_schemas.ex
defmodule EdgeAdminWeb.Schemas.CommonSchemas do
  @moduledoc """
  Common OpenAPI schemas shared across the application
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule ErrorResponse do
    @moduledoc false
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

    OpenApiSpex.schema(%{
      title: "Not Found Response",
      description: "Resource not found error",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          properties: %{
            detail: %Schema{
              type: :string,
              description: "Error detail message"
            }
          },
          required: [:detail]
        }
      },
      required: [:errors],
      example: %{
        errors: %{
          detail: "Not Found"
        }
      }
    })
  end

  defmodule GenericErrorResponse do
    @moduledoc false

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

  defmodule PaginationMeta do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Pagination Metadata",
      description: "Pagination information for paginated responses",
      type: :object,
      properties: %{
        page: %Schema{type: :integer, description: "Current page number", example: 1},
        page_size: %Schema{type: :integer, description: "Items per page", example: 20},
        total: %Schema{type: :integer, description: "Total number of items", example: 150},
        total_pages: %Schema{type: :integer, description: "Total number of pages", example: 8},
        has_next: %Schema{
          type: :boolean,
          description: "Whether there's a next page",
          example: true
        },
        has_prev: %Schema{
          type: :boolean,
          description: "Whether there's a previous page",
          example: false
        }
      },
      required: [:page, :page_size, :total, :total_pages, :has_next, :has_prev]
    })
  end

  defmodule FilteringSortingMeta do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Filtering and Sorting Metadata",
      description: "Information about applied filters and sorting",
      type: :object,
      properties: %{
        filters: %Schema{
          type: :object,
          description: "Applied filters",
          additionalProperties: %Schema{type: :string},
          example: %{status: "healthy", id_type: "persistent_id"}
        },
        sort: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Applied sort order",
          example: ["status:desc", "inserted_at:asc"]
        }
      }
    })
  end

  @doc """
  Creates a paginated response schema for any data type.

  ## Parameters
  - `data_schema` - The schema for individual items
  - `title` - Title for the response schema
  - `description` - Description for the response schema

  ## Example
      defmodule NodePaginatedResponse do
        require OpenApiSpex

        OpenApiSpex.schema(
          CommonSchemas.paginated_response(
            NodeResponse,
            "Node Paginated Response",
            "Paginated list of nodes with metadata"
          )
        )
      end
  """
  def paginated_response(data_schema, title, description) do
    %{
      title: title,
      description: description,
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: data_schema
        },
        pagination: PaginationMeta,
        filters: %Schema{
          type: :object,
          description: "Applied filters",
          additionalProperties: %Schema{type: :string}
        },
        sort: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Applied sort order"
        }
      },
      required: [:data, :pagination]
    }
  end
end
