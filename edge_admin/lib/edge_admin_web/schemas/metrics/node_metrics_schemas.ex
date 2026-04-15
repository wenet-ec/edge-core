# edge_admin/lib/edge_admin_web/schemas/metrics/node_metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Metrics.NodeMetricsSchemas do
  @moduledoc """
  OpenAPI schemas for node metrics endpoints
  """
  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule HostMetricsResponse do
    @moduledoc "Host-level metrics response"

    schema(%{
      title: "HostMetricsResponse",
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

    schema(%{
      title: "AgentMetricsResponse",
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
                  description: "Memory used by BEAM processes in bytes"
                },
                memory_processes_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Memory used by BEAM processes in MB"
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
                  description: "Total command sync calls made to admin"
                },
                enqueued_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total command executions enqueued for local execution"
                },
                completed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total command executions completed"
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
                admins_found_last: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of admins discovered during the last scan"
                }
              }
            },
            proxy: %Schema{
              type: :object,
              description: "Proxy server connection and security metrics",
              properties: %{
                http_connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total HTTP proxy connections"
                },
                http_blocked_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total HTTP requests blocked by security rules"
                },
                http_blocked_by_reason: %Schema{
                  type: :object,
                  nullable: true,
                  description: "HTTP blocked requests grouped by reason",
                  additionalProperties: %Schema{type: :integer},
                  example: %{
                    "localhost_blocked" => 5,
                    "docker_network_blocked" => 3,
                    "metadata_service_blocked" => 2,
                    "docker_port_blocked" => 1
                  }
                },
                socks5_connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SOCKS5 proxy connections"
                },
                socks5_blocked_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SOCKS5 requests blocked by security rules"
                },
                socks5_blocked_by_reason: %Schema{
                  type: :object,
                  nullable: true,
                  description: "SOCKS5 blocked requests grouped by reason",
                  additionalProperties: %Schema{type: :integer},
                  example: %{
                    "localhost_blocked" => 3,
                    "kubernetes_port_blocked" => 2
                  }
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
                  description: "Total SSH authentication attempts (all methods)"
                },
                connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SSH connections established"
                }
              }
            },
            vpn: %Schema{
              type: :object,
              description: "VPN connectivity metrics",
              properties: %{
                pulls_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description:
                    "Total VPN config pulls performed (daily backstop for DNS recovery after netclient restart)"
                }
              }
            },
            health_check: %Schema{
              type: :object,
              description:
                "Health check report metrics (only active when VPN is down and agent is in HTTP fallback mode)",
              properties: %{
                reports_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total health check reports sent to admin via HTTP fallback"
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
                  available: %Schema{type: :integer, description: "Jobs available to run"},
                  executing: %Schema{type: :integer, description: "Jobs currently executing"},
                  completed: %Schema{type: :integer, description: "Completed jobs"},
                  discarded: %Schema{type: :integer, description: "Discarded jobs (max retries exceeded)"},
                  retryable: %Schema{type: :integer, description: "Jobs awaiting retry"}
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
            memory_ets_bytes: 4_194_304,
            memory_ets_mb: 4.0,
            memory_binary_bytes: 2_097_152,
            memory_binary_mb: 2.0
          },
          commands: %{
            synced_total: 156,
            enqueued_total: 152,
            completed_total: 150,
            reported_total: 150
          },
          discovery: %{
            scans_total: 48,
            admins_found_last: 5
          },
          proxy: %{
            http_connections_total: 523,
            http_blocked_total: 15,
            http_blocked_by_reason: %{
              "localhost_blocked" => 8,
              "docker_network_blocked" => 4,
              "metadata_service_blocked" => 2,
              "agent_port_blocked" => 1
            },
            socks5_connections_total: 87,
            socks5_blocked_total: 5,
            socks5_blocked_by_reason: %{
              "localhost_blocked" => 3,
              "docker_port_blocked" => 2
            }
          },
          ssh: %{
            authentications_total: 45,
            connections_total: 44
          },
          vpn: %{
            pulls_total: 7
          },
          health_check: %{
            reports_total: 0
          },
          oban_queues: [
            %{
              queue: "default",
              available: 0,
              executing: 1,
              completed: 245,
              discarded: 1,
              retryable: 0
            },
            %{
              queue: "commands",
              available: 0,
              executing: 0,
              completed: 150,
              discarded: 0,
              retryable: 0
            }
          ]
        }
      }
    })
  end

  defmodule UnifiedMetricsResponse do
    @moduledoc "Unified metrics from all sources"

    schema(%{
      title: "UnifiedMetricsResponse",
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
            host: %Schema{
              type: :object,
              description: "Host-level metrics from Node Exporter",
              properties: %{
                available: %Schema{type: :boolean, description: "Whether host metrics were successfully fetched"},
                cpu: %Schema{type: :object, nullable: true, description: "CPU metrics"},
                memory: %Schema{type: :object, nullable: true, description: "Memory metrics"},
                disk: %Schema{type: :object, nullable: true, description: "Disk metrics"},
                uptime: %Schema{type: :object, nullable: true, description: "Uptime information"}
              }
            },
            agent: %Schema{
              type: :object,
              description: "Agent application metrics from PromEx",
              properties: %{
                available: %Schema{type: :boolean, description: "Whether agent metrics were successfully fetched"},
                application: %Schema{type: :object, nullable: true, description: "BEAM VM stats"},
                commands: %Schema{type: :object, nullable: true, description: "Command execution metrics"},
                discovery: %Schema{type: :object, nullable: true, description: "Admin discovery metrics"},
                proxy: %Schema{type: :object, nullable: true, description: "Proxy server metrics"},
                ssh: %Schema{type: :object, nullable: true, description: "SSH server metrics"},
                vpn: %Schema{type: :object, nullable: true, description: "VPN config pull metrics"},
                health_check: %Schema{
                  type: :object,
                  nullable: true,
                  description: "Health check report metrics (HTTP fallback mode)"
                },
                oban_queues: %Schema{
                  type: :array,
                  nullable: true,
                  description: "Oban job queue states",
                  items: %Schema{type: :object}
                }
              }
            }
          },
          required: [:node_id, :cluster_name, :timestamp]
        },
        meta: EdgeAdminWeb.Schemas.CommonSchemas.MetaSchema
      },
      required: [:data, :meta]
    })
  end
end
