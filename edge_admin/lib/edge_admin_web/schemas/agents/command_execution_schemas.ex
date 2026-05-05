# edge_admin/lib/edge_admin_web/schemas/agents/command_execution_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.CommandExecutionSchemas do
  @moduledoc """
  OpenAPI schemas for agent command execution endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule UpdateCommandExecutionResultRequest do
    @moduledoc false

    schema(%{
      title: "Internal.UpdateCommandExecutionResultRequest",
      description: "Command execution result reported by the agent.",
      type: :object,
      additionalProperties: true,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["completed", "expired"],
          description: "Terminal status reported by the agent"
        },
        output: %Schema{type: :string, nullable: true, description: "Command output text"},
        exit_code: %Schema{type: :integer, nullable: true, description: "Process exit code"},
        completed_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the command completed (defaults to now if omitted)"
        }
      },
      required: [:status]
    })
  end

  defmodule AgentCommandExecutionResponse do
    @moduledoc false

    schema(%{
      title: "Internal.AgentCommandExecutionResponse",
      description: "Command execution as seen by the agent (subset of admin fields)",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Command execution UUID"},
        command_id: %Schema{type: :string, format: :uuid, description: "Parent command UUID"},
        command_text: %Schema{
          type: :string,
          nullable: true,
          description: "The command text to execute",
          example: "systemctl restart nginx"
        },
        timeout: %Schema{
          type: :integer,
          nullable: true,
          description: "Execution timeout in milliseconds (null means no timeout)"
        },
        status: %Schema{
          type: :string,
          enum: ["pending", "sent", "completed", "cancelled", "expired"],
          description: "Current execution status"
        },
        expired_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "The expiration deadline from the parent command (null if no expiration was set)"
        },
        inserted_at: %Schema{type: :string, format: :"date-time", description: "When the execution was created"}
      },
      required: [:id, :command_id, :status, :inserted_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        command_id: "fedcba98-7654-3210-fedc-ba9876543210",
        command_text: "systemctl restart nginx",
        timeout: 30_000,
        status: "pending",
        inserted_at: "2026-04-02T10:00:00Z"
      }
    })
  end

  defmodule AgentCommandExecutionSingleResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        AgentCommandExecutionResponse,
        "Internal.AgentCommandExecutionSingleResponse",
        "Single command execution response for agent"
      )
    )
  end

  defmodule AgentCommandExecutionPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        AgentCommandExecutionResponse,
        "AgentCommandExecutionPaginatedResponse",
        "Paginated list of command executions for the agent"
      )
    )
  end
end
