# edge_admin/lib/edge_admin_web/schemas/metrics/admin_metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Metrics.AdminMetricsSchemas do
  @moduledoc """
  OpenAPI schemas for admin metrics endpoints
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule AdminMetricsResponse do
    @moduledoc "Admin application metrics response"

    OpenApiSpex.schema(%{
      title: "Admin Metrics Response",
      description: """
      Application-level metrics from edge_admin PromEx (BEAM stats, metadata, Oban, etc.).
      """,
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            timestamp: %Schema{
              type: :string,
              format: :"date-time",
              description: "When the metrics were collected (ISO 8601 format)"
            },
            application: %Schema{
              type: :object,
              description: "Application health and BEAM VM stats",
              properties: %{
                uptime_seconds: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Application uptime in seconds"
                },
                uptime_human: %Schema{
                  type: :string,
                  nullable: true,
                  description: "Human-readable uptime (e.g., '2d 5h 30m')"
                },
                process_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of BEAM processes running"
                },
                port_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of active ports"
                },
                atom_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of allocated atoms"
                },
                ets_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of ETS tables"
                },
                memory_total_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total BEAM memory allocated in bytes"
                },
                memory_total_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Total BEAM memory in MB"
                },
                memory_processes_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Memory used by processes in bytes"
                },
                memory_processes_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by processes in MB"
                },
                memory_ets_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Memory used by ETS tables in bytes"
                },
                memory_ets_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by ETS tables in MB"
                },
                memory_binary_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Memory used by binaries in bytes"
                },
                memory_binary_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by binaries in MB"
                },
                memory_code_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Memory used by code in bytes"
                },
                memory_code_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by code in MB"
                },
                memory_atom_bytes: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Memory used by atoms in bytes"
                },
                memory_atom_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by atoms in MB"
                }
              }
            },
            metadata: %Schema{
              type: :object,
              description: "Admin metadata and cluster assignment status",
              properties: %{
                degraded: %Schema{
                  type: :boolean,
                  nullable: true,
                  description: "Whether admin is in degraded state"
                },
                orphaned_clusters: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of orphaned clusters detected"
                },
                assigned_clusters: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of clusters assigned to this admin"
                },
                recomputations_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total metadata recomputations performed"
                }
              }
            },
            bootstrap: %Schema{
              type: :object,
              description: "Bootstrap initialization metrics",
              properties: %{
                steps_completed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total bootstrap steps completed"
                }
              }
            },
            nodes: %Schema{
              type: :object,
              description: "Node health check metrics",
              properties: %{
                health_checks_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total node health checks performed"
                }
              }
            },
            quantum: %Schema{
              type: :object,
              description: "Quantum scheduler job execution metrics",
              properties: %{
                jobs_executed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total Quantum jobs executed across all job types"
                },
                jobs_exceptions_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total Quantum job exceptions/failures"
                }
              }
            },
            vpn: %Schema{
              type: :object,
              description: "VPN management metrics",
              properties: %{
                zombie_cleanup_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total zombie admin cleanup runs"
                },
                zombie_cleanup_deleted_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of zombie admins deleted in last cleanup"
                }
              }
            },
            commands: %Schema{
              type: :object,
              description: "Command execution and delivery metrics",
              properties: %{
                delivery_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total execution delivery runs"
                },
                delivery_delivered_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of executions delivered in last run"
                }
              }
            },
            gateways: %Schema{
              type: :object,
              description: "Gateway connection and scrape metrics",
              properties: %{
                connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total gateway connection events (connects + disconnects)"
                },
                active_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Current number of active gateway connections"
                },
                scrapes_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total metrics scrape operations performed by gateways"
                }
              }
            },
            oban_queues: %Schema{
              type: :array,
              description: "Oban job queue states",
              items: %Schema{
                type: :object,
                properties: %{
                  queue: %Schema{
                    type: :string,
                    description: "Queue name (e.g., 'zombie_admin_cleanup', 'execution_creation')"
                  },
                  available: %Schema{
                    type: :integer,
                    description: "Jobs available to run"
                  },
                  scheduled: %Schema{
                    type: :integer,
                    description: "Jobs scheduled for future execution"
                  },
                  executing: %Schema{
                    type: :integer,
                    description: "Jobs currently executing"
                  },
                  retryable: %Schema{
                    type: :integer,
                    description: "Jobs awaiting retry"
                  },
                  completed: %Schema{
                    type: :integer,
                    description: "Completed jobs"
                  },
                  discarded: %Schema{
                    type: :integer,
                    description: "Discarded jobs (max retries exceeded)"
                  },
                  cancelled: %Schema{
                    type: :integer,
                    description: "Cancelled jobs"
                  }
                }
              }
            }
          }
        }
      },
      example: %{
        data: %{
          timestamp: "2025-12-26T15:30:00Z",
          application: %{
            uptime_seconds: 1404,
            uptime_human: "23m",
            process_count: 811,
            port_count: 31,
            atom_count: 38522,
            ets_count: 144,
            memory_total_bytes: 101_185_152,
            memory_total_mb: 96.5,
            memory_processes_bytes: 25_999_000,
            memory_processes_mb: 24.79,
            memory_ets_bytes: 2_884_160,
            memory_ets_mb: 2.75,
            memory_binary_bytes: 8_817_904,
            memory_binary_mb: 8.41,
            memory_code_bytes: 30_935_279,
            memory_code_mb: 29.5,
            memory_atom_bytes: 1_223_807,
            memory_atom_mb: 1.17
          },
          metadata: %{
            degraded: false,
            orphaned_clusters: 0,
            assigned_clusters: 0,
            recomputations_total: 26
          },
          bootstrap: %{
            steps_completed_total: 4
          },
          nodes: %{
            health_checks_total: 1
          },
          quantum: %{
            jobs_executed_total: 156,
            jobs_exceptions_total: 0
          },
          vpn: %{
            zombie_cleanup_total: 81,
            zombie_cleanup_deleted_count: 0
          },
          commands: %{
            delivery_total: 48,
            delivery_delivered_count: 0
          },
          gateways: %{
            connections_total: 2,
            active_count: 0,
            scrapes_total: 0
          },
          oban_queues: [
            %{
              queue: "zombie_admin_cleanup",
              available: 0,
              scheduled: 0,
              executing: 0,
              retryable: 0,
              completed: 81,
              discarded: 0,
              cancelled: 0
            },
            %{
              queue: "execution_creation",
              available: 0,
              scheduled: 0,
              executing: 0,
              retryable: 0,
              completed: 0,
              discarded: 0,
              cancelled: 0
            }
          ]
        }
      }
    })
  end
end
