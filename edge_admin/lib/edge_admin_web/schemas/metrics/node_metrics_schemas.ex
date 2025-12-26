# edge_admin/lib/edge_admin_web/schemas/metrics/node_metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Metrics.NodeMetricsSchemas do
  @moduledoc """
  OpenAPI schemas for node metrics endpoints
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule HostMetricsResponse do
    @moduledoc "Host-level metrics response"

    OpenApiSpex.schema(%{
      title: "Host Metrics Response",
      description: """
      Host-level system metrics from Node Exporter (CPU, memory, disk, uptime).
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

  defmodule AgentMetricsResponse do
    @moduledoc "Agent application metrics response"

    OpenApiSpex.schema(%{
      title: "Agent Metrics Response",
      description: """
      Application-level metrics from edge_agent PromEx (BEAM stats, Oban, business metrics).
      """,
      type: :object,
      properties: %{
        data: %Schema{
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
                schedulers_online: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of active BEAM schedulers"
                },
                run_queue: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of processes in the run queue"
                },
                gc_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Garbage collection count"
                },
                gc_words_reclaimed: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Words reclaimed by garbage collection"
                }
              }
            },
            commands: %Schema{
              type: :object,
              description: "Command execution metrics",
              properties: %{
                synced_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total commands synced from admin"
                },
                enqueued_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total commands enqueued for execution"
                },
                executed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total commands executed"
                },
                reported_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total results reported back to admin"
                }
              }
            },
            discovery: %Schema{
              type: :object,
              description: "Admin discovery metrics",
              properties: %{
                scans_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total discovery scans performed"
                },
                admins_found_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total admins discovered (cumulative)"
                }
              }
            },
            proxy: %Schema{
              type: :object,
              description: "Proxy server connection metrics",
              properties: %{
                http_connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total HTTP proxy connections"
                },
                http_connections_success: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Successful HTTP connections"
                },
                http_connections_failed: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Failed HTTP connections"
                },
                socks5_connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SOCKS5 proxy connections"
                },
                socks5_connections_success: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Successful SOCKS5 connections"
                },
                socks5_connections_failed: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Failed SOCKS5 connections"
                }
              }
            },
            ssh: %Schema{
              type: :object,
              description: "SSH server metrics",
              properties: %{
                authentications_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total authentication attempts"
                },
                authentications_success: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Successful authentications"
                },
                authentications_failed: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Failed authentications"
                },
                connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SSH connections established"
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
                    description: "Queue name (e.g., 'default', 'commands')"
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
          node_id: "550e8400-e29b-41d4-a716-446655440000",
          cluster_name: "production",
          timestamp: "2025-01-15T15:30:00Z",
          application: %{
            uptime_seconds: 172_800,
            uptime_human: "2d 0h 0m",
            process_count: 342,
            memory_total_bytes: 125_829_120,
            memory_total_mb: 120.0,
            memory_processes_bytes: 83_886_080,
            memory_processes_mb: 80.0,
            schedulers_online: 4,
            run_queue: 0,
            gc_count: 1234,
            gc_words_reclaimed: 5_678_901
          },
          commands: %{
            synced_total: 156,
            enqueued_total: 152,
            executed_total: 150,
            reported_total: 150
          },
          discovery: %{
            scans_total: 48,
            admins_found_total: 96
          },
          proxy: %{
            http_connections_total: 523,
            http_connections_success: 520,
            http_connections_failed: 3,
            socks5_connections_total: 87,
            socks5_connections_success: 85,
            socks5_connections_failed: 2
          },
          ssh: %{
            authentications_total: 45,
            authentications_success: 44,
            authentications_failed: 1,
            connections_total: 44
          },
          oban_queues: [
            %{
              queue: "default",
              available: 0,
              scheduled: 2,
              executing: 1,
              retryable: 0,
              completed: 245,
              discarded: 1,
              cancelled: 0
            },
            %{
              queue: "commands",
              available: 0,
              scheduled: 5,
              executing: 0,
              retryable: 0,
              completed: 150,
              discarded: 0,
              cancelled: 0
            }
          ]
        }
      }
    })
  end

  defmodule UnifiedMetricsResponse do
    @moduledoc "Unified metrics from all sources"

    OpenApiSpex.schema(%{
      title: "Unified Metrics Response",
      description: """
      Complete metrics from all sources: host (Node Exporter) and agent (PromEx).
      Provides a unified view of node health and performance.
      Uses best-effort fetching - if one source fails, it's marked as unavailable.
      """,
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            node_id: %Schema{
              type: :string,
              format: :uuid
            },
            cluster_name: %Schema{
              type: :string
            },
            timestamp: %Schema{
              type: :string,
              format: :"date-time"
            },
            host: %Schema{
              type: :object,
              description: "Host-level metrics from Node Exporter",
              properties: %{
                available: %Schema{type: :boolean},
                cpu: %Schema{type: :object, nullable: true},
                memory: %Schema{type: :object, nullable: true},
                disk: %Schema{type: :object, nullable: true},
                uptime: %Schema{type: :object, nullable: true}
              }
            },
            agent: %Schema{
              type: :object,
              description: "Agent application metrics from PromEx",
              properties: %{
                available: %Schema{type: :boolean},
                application: %Schema{type: :object, nullable: true},
                commands: %Schema{type: :object, nullable: true},
                discovery: %Schema{type: :object, nullable: true},
                proxy: %Schema{type: :object, nullable: true},
                ssh: %Schema{type: :object, nullable: true},
                oban_queues: %Schema{type: :array, nullable: true}
              }
            }
          }
        }
      }
    })
  end
end
