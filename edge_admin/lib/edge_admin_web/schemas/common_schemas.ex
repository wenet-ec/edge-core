# edge_admin/lib/edge_admin_web/schemas/common_schemas.ex
defmodule EdgeAdminWeb.Schemas.CommonSchemas do
  @moduledoc """
  Common OpenAPI schemas shared across the application
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule ChangesetErrorResponse do
    @moduledoc false
    schema(%{
      title: "ChangesetErrorResponse",
      description: "Validation error response from Ecto changeset (422 Unprocessable Entity)",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          description: "Field-specific validation errors",
          additionalProperties: %Schema{
            type: :array,
            items: %Schema{type: :string}
          }
        }
      },
      required: [:errors],
      example: %{
        errors: %{
          name: ["can't be blank"],
          email: ["has already been taken", "must have the @ sign"]
        }
      }
    })
  end

  defmodule NotFoundResponse do
    @moduledoc false

    schema(%{
      title: "NotFoundResponse",
      description: "Resource not found error (404)",
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

  defmodule UnauthorizedResponse do
    @moduledoc false

    schema(%{
      title: "UnauthorizedResponse",
      description: "Authentication required or invalid credentials (401)",
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
          detail: "Unauthorized"
        }
      }
    })
  end

  defmodule ForbiddenResponse do
    @moduledoc false

    schema(%{
      title: "ForbiddenResponse",
      description: "Insufficient permissions to access resource (403)",
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
          detail: "Forbidden"
        }
      }
    })
  end

  defmodule ConflictResponse do
    @moduledoc false

    schema(%{
      title: "ConflictResponse",
      description: "Resource conflict, usually duplicate or constraint violation (409)",
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
          detail: "Conflict"
        }
      }
    })
  end

  defmodule ServiceUnavailableResponse do
    @moduledoc false

    schema(%{
      title: "ServiceUnavailableResponse",
      description: "Downstream service unavailable (503)",
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
          detail: "Service Unavailable"
        }
      }
    })
  end

  defmodule BadRequestResponse do
    @moduledoc false

    schema(%{
      title: "BadRequestResponse",
      description: "Malformed request or invalid input (400)",
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
          detail: "Bad Request"
        }
      }
    })
  end

  defmodule InternalServerErrorResponse do
    @moduledoc false

    schema(%{
      title: "InternalServerErrorResponse",
      description: "Unexpected server error (500)",
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
          detail: "Internal Server Error"
        }
      }
    })
  end

  defmodule PaginationMeta do
    @moduledoc false

    schema(%{
      title: "PaginationMetadata",
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

  @doc """
  Creates a paginated response schema for any data type.

  ## Parameters
  - `data_schema` - The schema for individual items
  - `title` - Title for the response schema
  - `description` - Description for the response schema

  ## Example
      defmodule NodePaginatedResponse do
        use EdgeAdminWeb.Schema

        schema(
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
        pagination: PaginationMeta
      },
      required: [:data, :pagination]
    }
  end
end
