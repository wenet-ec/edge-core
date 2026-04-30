# edge_admin/lib/edge_admin_web/schemas/common_schemas.ex
defmodule EdgeAdminWeb.Schemas.CommonSchemas do
  @moduledoc """
  Common OpenAPI schemas shared across the application.

  Every response — success or error — is wrapped in the standard envelope:
    - Success single:     %{data: %{...}, meta: %{request_id, timestamp}}
    - Success paginated:  %{data: [...], meta: %{request_id, timestamp, pagination: %{...}}}
    - Error:              %{error: %{code, message, details}, meta: %{request_id, timestamp}}
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  # ---------------------------------------------------------------------------
  # Meta schemas
  # ---------------------------------------------------------------------------

  defmodule MetaSchema do
    @moduledoc false

    schema(%{
      title: "Meta",
      description: "Request metadata present on every response",
      type: :object,
      properties: %{
        request_id: %Schema{
          type: :string,
          description: "Unique request identifier (mirrors x-request-id response header)",
          example: "550e8400-e29b-41d4-a716-446655440000"
        },
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "ISO 8601 UTC timestamp of when the response was generated",
          example: "2026-04-15T10:00:00.000Z"
        }
      },
      required: [:request_id, :timestamp]
    })
  end

  defmodule PaginationSchema do
    @moduledoc false

    schema(%{
      title: "Pagination",
      description: "Pagination metadata for list responses",
      type: :object,
      properties: %{
        page: %Schema{type: :integer, description: "Current page number", example: 1},
        page_size: %Schema{type: :integer, description: "Items per page", example: 20},
        total_count: %Schema{type: :integer, description: "Total number of items", example: 150},
        total_pages: %Schema{type: :integer, description: "Total number of pages", example: 8},
        has_next: %Schema{type: :boolean, description: "Whether a next page exists", example: true},
        has_prev: %Schema{type: :boolean, description: "Whether a previous page exists", example: false},
        next_page: %Schema{
          type: :integer,
          nullable: true,
          description: "Next page number, null when on the last page",
          example: 2
        },
        prev_page: %Schema{
          type: :integer,
          nullable: true,
          description: "Previous page number, null when on the first page",
          example: nil
        }
      },
      required: [:page, :page_size, :total_count, :total_pages, :has_next, :has_prev, :next_page, :prev_page]
    })
  end

  defmodule PaginatedMetaSchema do
    @moduledoc false

    schema(%{
      title: "PaginatedMeta",
      description: "Meta object for paginated list responses (includes pagination block)",
      type: :object,
      properties: %{
        request_id: %Schema{
          type: :string,
          description: "Unique request identifier",
          example: "550e8400-e29b-41d4-a716-446655440000"
        },
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "ISO 8601 UTC response timestamp",
          example: "2026-04-15T10:00:00.000Z"
        },
        pagination: PaginationSchema
      },
      required: [:request_id, :timestamp, :pagination]
    })
  end

  # ---------------------------------------------------------------------------
  # Unified error response
  # ---------------------------------------------------------------------------

  defmodule ErrorResponse do
    @moduledoc false

    schema(%{
      title: "ErrorResponse",
      description: "Standard error envelope returned for all error HTTP status codes",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{
              type: :string,
              enum: [
                "bad_request",
                "unauthorized",
                "forbidden",
                "not_found",
                "conflict",
                "validation_failed",
                "internal_server_error",
                "service_unavailable"
              ],
              description: "Machine-readable error code"
            },
            message: %Schema{
              type: :string,
              description: "Human-readable error message",
              example: "Resource not found"
            },
            details: %Schema{
              nullable: true,
              description:
                "Field-level validation errors (only present for validation_failed). " <>
                  "Shape mirrors Ecto.Changeset.traverse_errors/2: field -> [msg, ...], " <>
                  "nested for embeds/associations.",
              example: %{
                name: ["can't be blank"],
                timeout: ["must be greater than 0"]
              }
            }
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{
          code: "not_found",
          message: "Resource not found"
        },
        meta: %{
          request_id: "550e8400-e29b-41d4-a716-446655440000",
          timestamp: "2026-04-15T10:00:00.000Z"
        }
      }
    })
  end

  # Convenience aliases used in controller operation specs.
  # Each has its own title (= its own $ref in the OpenAPI spec) and a matching example.
  # They cannot share ErrorResponse's title — OpenApiSpex uses the title as the component key,
  # so modules with the same title collapse into one $ref and share the same example in Swagger UI.

  defmodule NotFoundResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "NotFoundResponse",
      description: "404 Not Found",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "not_found"},
            message: %Schema{type: :string, example: "Resource not found"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "not_found", message: "Resource not found"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule UnauthorizedResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "UnauthorizedResponse",
      description: "401 Unauthorized",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "unauthorized"},
            message: %Schema{type: :string, example: "Missing or invalid credentials"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "unauthorized", message: "Missing or invalid credentials"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule ForbiddenResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "ForbiddenResponse",
      description: "403 Forbidden",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "forbidden"},
            message: %Schema{type: :string, example: "Insufficient permissions"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "forbidden", message: "Insufficient permissions"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule ConflictResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "ConflictResponse",
      description: "409 Conflict",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "conflict"},
            message: %Schema{type: :string, example: "Resource already exists"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "conflict", message: "Resource already exists"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule BadRequestResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "BadRequestResponse",
      description: "400 Bad Request",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "bad_request"},
            message: %Schema{type: :string, example: "Invalid request parameters"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{
          code: "bad_request",
          message: "Invalid request parameters",
          details: %{name: ["Invalid format. Expected ~r/^[a-z0-9]/"], ipv4_range: ["Invalid format."]}
        },
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule ServiceUnavailableResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "ServiceUnavailableResponse",
      description: "503 Service Unavailable",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "service_unavailable"},
            message: %Schema{type: :string, example: "Downstream dependency unreachable"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "service_unavailable", message: "Downstream dependency unreachable"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule InternalServerErrorResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "InternalServerErrorResponse",
      description: "500 Internal Server Error",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "internal_server_error"},
            message: %Schema{type: :string, example: "An unexpected error occurred"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{code: "internal_server_error", message: "An unexpected error occurred"},
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  defmodule ChangesetErrorResponse do
    @moduledoc false
    use EdgeAdminWeb.Schema

    schema(%{
      title: "ChangesetErrorResponse",
      description: "422 Validation Failed",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, example: "validation_failed"},
            message: %Schema{type: :string, example: "Validation failed"},
            details: %Schema{nullable: true}
          },
          required: [:code, :message]
        },
        meta: MetaSchema
      },
      required: [:error, :meta],
      example: %{
        error: %{
          code: "validation_failed",
          message: "Validation failed",
          details: %{name: ["can't be blank"], timeout: ["must be greater than 0"]}
        },
        meta: %{request_id: "550e8400-e29b-41d4-a716-446655440000", timestamp: "2026-04-15T10:00:00.000Z"}
      }
    })
  end

  # ---------------------------------------------------------------------------
  # Helper — builds a paginated response schema for any resource schema.
  # Used by *PaginatedResponse modules in each resource schema file.
  # ---------------------------------------------------------------------------

  @doc """
  Builds a paginated response schema wrapping `data_schema` items.

  ## Example

      defmodule NodePaginatedResponse do
        use EdgeAdminWeb.Schema
        schema(CommonSchemas.paginated_response(NodeResponse, "NodePaginatedResponse", "Paginated nodes"))
      end
  """
  def paginated_response(data_schema, title, description) do
    %{
      title: title,
      description: description,
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: data_schema},
        meta: PaginatedMetaSchema
      },
      required: [:data, :meta]
    }
  end

  @doc """
  Builds a single-resource response schema wrapping `data_schema`.

  ## Example

      defmodule NodeSingleResponse do
        use EdgeAdminWeb.Schema
        schema(CommonSchemas.single_response(NodeResponse, "NodeSingleResponse", "Single node"))
      end
  """
  def single_response(data_schema, title, description) do
    %{
      title: title,
      description: description,
      type: :object,
      properties: %{
        data: data_schema,
        meta: MetaSchema
      },
      required: [:data, :meta]
    }
  end
end
