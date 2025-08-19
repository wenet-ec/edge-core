# edge_admin/lib/edge_admin_web/schemas/nodes/metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.MetricsSchemas do
  @moduledoc false
  defmodule MetricsResponse do
    @moduledoc false
    alias OpenApiSpex.Schema

    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Metrics Response",
      description: "Current system metrics for a specific node with detailed breakdowns",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            node_id: %Schema{
              type: :string,
              format: :uuid,
              description: "Node identifier"
            },
            timestamp: %Schema{
              type: :string,
              format: :datetime,
              description: "When the metrics were retrieved"
            },
            cpu: %Schema{
              type: :object,
              properties: %{
                usage_percent: %Schema{
                  type: :number,
                  nullable: true,
                  description: "CPU usage percentage (0-100)"
                },
                cores: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of CPU cores"
                },
                load_1m: %Schema{
                  type: :number,
                  nullable: true,
                  description: "1-minute load average"
                },
                load_5m: %Schema{
                  type: :number,
                  nullable: true,
                  description: "5-minute load average"
                },
                load_15m: %Schema{
                  type: :number,
                  nullable: true,
                  description: "15-minute load average"
                }
              }
            },
            memory: %Schema{
              type: :object,
              properties: %{
                usage_percent: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory usage percentage (0-100)"
                },
                total_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total memory in bytes"
                },
                available_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Available memory in bytes"
                },
                used_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Used memory in bytes"
                },
                total_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Total memory in GB"
                },
                available_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Available memory in GB"
                },
                used_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Used memory in GB"
                }
              }
            },
            disk: %Schema{
              type: :object,
              properties: %{
                usage_percent: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Disk usage percentage (0-100)"
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
                  description: "Used disk space in bytes"
                },
                total_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Total disk space in GB"
                },
                available_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Available disk space in GB"
                },
                used_gb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Used disk space in GB"
                }
              }
            },
            network: %Schema{
              type: :object,
              properties: %{
                rx_bytes_per_sec: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Bytes received per second"
                },
                tx_bytes_per_sec: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Bytes transmitted per second"
                },
                rx_packets_per_sec: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Packets received per second"
                },
                tx_packets_per_sec: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Packets transmitted per second"
                }
              }
            },
            uptime: %Schema{
              type: :object,
              properties: %{
                seconds: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "System uptime in seconds"
                },
                human: %Schema{
                  type: :string,
                  nullable: true,
                  description: "Human-readable uptime (e.g., '1d 2h 30m')"
                }
              }
            }
          },
          required: [:node_id, :timestamp]
        }
      },
      required: [:data],
      example: %{
        data: %{
          node_id: "550e8400-e29b-41d4-a716-446655440000",
          timestamp: "2025-06-26T15:30:00Z",
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
          network: %{
            rx_bytes_per_sec: 1024.5,
            tx_bytes_per_sec: 2048.3,
            rx_packets_per_sec: 12.5,
            tx_packets_per_sec: 18.7
          },
          uptime: %{
            seconds: 90_061,
            human: "1d 1h 1m"
          }
        }
      }
    })
  end
end
