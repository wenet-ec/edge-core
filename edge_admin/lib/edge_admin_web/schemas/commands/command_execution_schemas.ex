# edge_admin/lib/edge_admin_web/schemas/commands/command_execution_schemas.ex
defmodule EdgeAdminWeb.Schemas.Commands.CommandExecutionSchemas do
  @moduledoc """
  OpenAPI schemas for Command Execution resources
  """

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule CommandExecutionResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Command Execution",
      description: "Command execution information",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique command execution identifier"
        },
        command_id: %Schema{
          type: :string,
          format: :uuid,
          description: "ID of the command being executed"
        },
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "ID of the target node"
        },
        cluster_name: %Schema{
          type: :string,
          nullable: true,
          description: "Name of the target cluster (null if cluster_id is null)"
        },
        target_all: %Schema{
          type: :boolean,
          description: "Whether this execution was created from a system-wide command"
        },
        status: %Schema{
          type: :string,
          enum: ["pending", "sent", "completed"],
          description: "Current execution status"
        },
        command_text: %Schema{
          type: :string,
          nullable: true,
          description: "The command text being executed (denormalized for convenience)",
          example: "echo hello\nls -la"
        },
        output: %Schema{
          type: :string,
          nullable: true,
          description: "Combined output from command execution",
          example:
            "$ ABC=value\n$ echo $ABC\nvalue\n$ systemctl restart nginx\nFailed to restart nginx.service: Unit not found\n"
        },
        exit_code: %Schema{
          type: :integer,
          nullable: true,
          description: "Final exit code (0 = success, non-zero = failure)",
          example: 5
        },
        sent_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "When the command was sent to the agent"
        },
        completed_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "When the command execution was completed"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the execution was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the execution was last updated"
        }
      },
      required: [:id, :command_id, :node_id, :target_all, :status, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        command_id: "fedcba98-7654-3210-fedc-ba9876543210",
        node_id: "abcdef01-2345-6789-abcd-ef0123456789",
        cluster_id: "aaaabbbb-cccc-dddd-eeee-ffffffffffff",
        cluster_name: "prod",
        target_all: false,
        status: "completed",
        command_text: "echo hello\nls -la",
        output:
          "$ ABC=value\n$ echo $ABC\nvalue\n$ systemctl restart nginx\nFailed to restart nginx.service: Unit not found\n",
        exit_code: 5,
        sent_at: "2025-06-17T10:30:00Z",
        completed_at: "2025-06-17T10:31:00Z",
        inserted_at: "2025-06-17T10:30:00Z",
        updated_at: "2025-06-17T10:31:00Z"
      }
    })
  end

  defmodule CommandExecutionPaginatedResponse do
    @moduledoc false

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        CommandExecutionResponse,
        "Command Execution Paginated Response",
        "Paginated list of command executions with filtering and sorting metadata"
      )
    )
  end

  defmodule CommandExecutionSingleResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Command Execution Single Response",
      description: "Single command execution response",
      type: :object,
      properties: %{
        data: CommandExecutionResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          command_id: "98765432-fedc-ba98-7654-321098765432",
          node_id: "11111111-2222-3333-4444-555555555555",
          cluster_id: nil,
          cluster_name: nil,
          target_all: false,
          status: "completed",
          command_text: "echo hello\npwd",
          output: "$ echo hello\nhello\n$ pwd\n/home/user",
          exit_code: 0,
          sent_at: "2025-06-17T12:00:00Z",
          completed_at: "2025-06-17T12:00:05Z",
          inserted_at: "2025-06-17T12:00:00Z",
          updated_at: "2025-06-17T12:00:05Z"
        }
      }
    })
  end

  defmodule CancelExecutionResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Cancel Execution Response",
      description: "Response from command execution cancellation request",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            result: %Schema{
              type: :string,
              description: "Cancellation request status message",
              example: "cancellation request sent"
            }
          },
          required: [:result]
        }
      },
      required: [:data],
      example: %{
        data: %{
          result: "cancellation request sent"
        }
      }
    })
  end
end
