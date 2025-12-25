# edge_admin/lib/edge_admin_web/schemas/nodes/node_metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeMetricsSchemas do
  @moduledoc """
  OpenAPI schemas for Node Metrics resources
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule MetricsResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Node Metrics Response",
      description: """
      Current system metrics for a specific node, parsed from raw Prometheus metrics.

      """,
      type: :object,
      properties: %{
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Node unique identifier"
        },
        cluster_name: %Schema{
          type: :string,
          description: "Name of the cluster this node belongs to"
        },
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the metrics were collected (ISO 8601 format)"
        },
        cpu: %Schema{
          type: :object,
          description: "CPU metrics",
          properties: %{
            cores: %Schema{
              type: :integer,
              nullable: true,
              description: "Number of CPU cores detected on the system"
            },
            load_1m: %Schema{
              type: :number,
              nullable: true,
              description: "System load average over the last 1 minute"
            },
            load_5m: %Schema{
              type: :number,
              nullable: true,
              description: "System load average over the last 5 minutes"
            },
            load_15m: %Schema{
              type: :number,
              nullable: true,
              description: "System load average over the last 15 minutes"
            }
          }
        },
        memory: %Schema{
          type: :object,
          description: "Memory metrics",
          properties: %{
            usage_percent: %Schema{
              type: :number,
              nullable: true,
              description: "Memory usage percentage calculated as (total - available) / total * 100"
            },
            total_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Total RAM in bytes"
            },
            available_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Available RAM in bytes (includes buffers/cache)"
            },
            used_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Used RAM in bytes (calculated as total - available)"
            },
            total_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Total RAM in gigabytes (GB)"
            },
            available_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Available RAM in gigabytes (GB)"
            },
            used_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Used RAM in gigabytes (GB)"
            }
          }
        },
        disk: %Schema{
          type: :object,
          description: "Disk metrics for root filesystem (/)",
          properties: %{
            usage_percent: %Schema{
              type: :number,
              nullable: true,
              description: "Disk usage percentage calculated as (total - available) / total * 100"
            },
            total_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Total disk space in bytes"
            },
            available_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Available disk space in bytes"
            },
            used_bytes: %Schema{
              type: :integer,
              nullable: true,
              description: "Used disk space in bytes (calculated as total - available)"
            },
            total_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Total disk space in gigabytes (GB)"
            },
            available_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Available disk space in gigabytes (GB)"
            },
            used_gb: %Schema{
              type: :number,
              nullable: true,
              description: "Used disk space in gigabytes (GB)"
            }
          }
        },
        uptime: %Schema{
          type: :object,
          description: "System uptime information",
          properties: %{
            seconds: %Schema{
              type: :integer,
              nullable: true,
              description: "System uptime in seconds since last boot"
            },
            human: %Schema{
              type: :string,
              nullable: true,
              description: "Human-readable uptime format (e.g., '1d 2h 30m', '5h 15m', '30m')"
            }
          }
        }
      },
      required: [:node_id, :cluster_name, :timestamp],
      example: %{
        node_id: "550e8400-e29b-41d4-a716-446655440000",
        cluster_name: "production",
        timestamp: "2025-01-15T15:30:00Z",
        cpu: %{
          usage_percent: 25.5,
          cores: 4,
          load_1m: 1.2,
          load_5m: 1.1,
          load_15m: 0.9
        },
        memory: %{
          usage_percent: 67.3,
          total_bytes: 8_589_934_592,
          available_bytes: 2_814_377_984,
          used_bytes: 5_775_556_608,
          total_gb: 8.0,
          available_gb: 2.6,
          used_gb: 5.4
        },
        disk: %{
          usage_percent: 45.8,
          total_bytes: 107_374_182_400,
          available_bytes: 58_249_036_800,
          used_bytes: 49_125_145_600,
          total_gb: 100.0,
          available_gb: 54.2,
          used_gb: 45.8
        },
        uptime: %{
          seconds: 90_061,
          human: "1d 1h 1m"
        }
      }
    })
  end
end
