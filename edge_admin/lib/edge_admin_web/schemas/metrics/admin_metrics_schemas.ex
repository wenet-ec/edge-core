# edge_admin/lib/edge_admin_web/schemas/metrics/admin_metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Metrics.AdminMetricsSchemas do
  @moduledoc """
  OpenAPI schemas for admin metrics endpoints
  """
  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule AdminMetricsResponse do
    @moduledoc "Admin application metrics response"

    schema(%{
      title: "AdminMetricsResponse",
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
            membership: %Schema{
              type: :object,
              description: "Admin-cluster membership initialization metrics",
              properties: %{
                steps_completed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total individual membership steps completed across all restarts"
                },
                complete_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total full membership sequences completed (success + failure)"
                }
              }
            },
            discovery: %Schema{
              type: :object,
              description: "Peer admin discovery metrics",
              properties: %{
                scans_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total peer discovery scan cycles completed"
                },
                dns_resolutions_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total DNS resolution attempts during peer discovery"
                },
                peer_connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total Erlang peer connection attempts (success + failure + already_connected)"
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
                  description: "Total delivery batch runs (Quantum scheduler cycles)"
                },
                delivery_delivered_count: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of executions queued for delivery in last batch run"
                },
                execution_delivered_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total individual execution delivery attempts to agents (success + failure)"
                },
                execution_completed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total executions completed (result reported back by agent)"
                },
                expiration_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total stale execution expiration sweeps"
                }
              }
            },
            ssh: %Schema{
              type: :object,
              description: "SSH credential verification metrics",
              properties: %{
                verifications_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SSH credential verification attempts (all auth methods)"
                },
                verifications_failed: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total SSH credential verification failures"
                }
              }
            },
            reconciliation: %Schema{
              type: :object,
              description: "Cluster reconciliation metrics (Netmaker ↔ DB sync)",
              properties: %{
                total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total cluster reconciliation runs"
                },
                errors: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Number of errors in last reconciliation run"
                }
              }
            },
            self_updates: %Schema{
              type: :object,
              description: "Self-update request processing metrics",
              properties: %{
                completed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total self-update requests processed to completion"
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
            proxy: %Schema{
              type: :object,
              description: "HTTP and SOCKS5 forward proxy metrics (connections, tunnels, bytes transferred)",
              properties: %{
                connections_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total proxy connections seen (success + auth_failed + failure)"
                },
                connections_success_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total proxy connections that authenticated and established a tunnel"
                },
                connections_auth_failed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total proxy connections rejected at authentication"
                },
                connections_failure_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description:
                    "Total proxy connections that failed for non-auth reasons (protocol, network, gateway, etc.)"
                },
                auth_failures_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total proxy authentication failures (mirrors connections_auth_failed_total)"
                },
                tunnels_closed_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total tunnels that reached end-of-life (all close reasons combined)"
                },
                tunnels_closed_normal_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Tunnels closed normally (both sides EOF'd cleanly)"
                },
                tunnels_closed_deadline_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Tunnels force-closed by the total-duration deadline (slowloris defence)"
                },
                tunnels_closed_drain_timeout_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Tunnels force-closed after exceeding the graceful drain grace window"
                },
                bytes_up_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Cumulative bytes forwarded client→target across all tunnels"
                },
                bytes_up_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Cumulative client→target bytes in MB"
                },
                bytes_down_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Cumulative bytes forwarded target→client across all tunnels"
                },
                bytes_down_mb: %Schema{
                  type: :number,
                  nullable: true,
                  description: "Cumulative target→client bytes in MB"
                }
              }
            },
            event_broker: %Schema{
              type: :object,
              description: """
              Event broker publish metrics. When the broker is disabled (default), `enabled` is `false`
              and all counters are 0. A sustained gap between `enqueues_total` and `publishes_ok_total`
              indicates broker failures with events accumulating in Oban for retry.
              """,
              properties: %{
                enabled: %Schema{
                  type: :boolean,
                  nullable: true,
                  description: "Whether the event broker is enabled (mirrors EVENT_BROKER_ENABLED config)"
                },
                enqueues_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total events enqueued for async broker delivery (before any publish attempt)"
                },
                publishes_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total broker publish attempts (ok + error)"
                },
                publishes_ok_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total broker publishes that succeeded"
                },
                publishes_error_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total broker publishes that failed (will be retried by Oban)"
                }
              }
            },
            webhook: %Schema{
              type: :object,
              description: """
              Webhook delivery metrics. `fan_outs_total` counts publish-time fan-out invocations
              (one per published event regardless of how many webhooks match). `deliveries_*` count
              individual HTTP delivery attempts and their outcomes — `ok`, `recoverable` (retried by
              Oban: 408/429/503/network until `WEBHOOK_MAX_ATTEMPTS` is exhausted), `terminal`
              (cancelled by the worker, no further retries).
              """,
              properties: %{
                fan_outs_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total fan-out invocations from the publish path"
                },
                deliveries_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total webhook delivery attempts (ok + recoverable + terminal)"
                },
                deliveries_ok_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total deliveries that returned 2xx"
                },
                deliveries_recoverable_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total deliveries that hit a recoverable error (will be retried)"
                },
                deliveries_terminal_total: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "Total deliveries that hit a terminal error (cancelled, contributes to auto-disable)"
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
            atom_count: 38_522,
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
          membership: %{
            steps_completed_total: 4,
            complete_total: 1
          },
          discovery: %{
            scans_total: 144,
            dns_resolutions_total: 12,
            peer_connections_total: 3
          },
          nodes: %{
            health_checks_total: 480
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
            delivery_delivered_count: 0,
            execution_delivered_total: 23,
            execution_completed_total: 21,
            expiration_total: 2
          },
          ssh: %{
            verifications_total: 34,
            verifications_failed: 1
          },
          reconciliation: %{
            total: 12,
            errors: 0
          },
          self_updates: %{
            completed_total: 3
          },
          gateways: %{
            connections_total: 2,
            active_count: 0,
            scrapes_total: 0
          },
          proxy: %{
            connections_total: 1245,
            connections_success_total: 1189,
            connections_auth_failed_total: 34,
            connections_failure_total: 22,
            auth_failures_total: 34,
            tunnels_closed_total: 1189,
            tunnels_closed_normal_total: 1140,
            tunnels_closed_deadline_total: 38,
            tunnels_closed_drain_timeout_total: 11,
            bytes_up_total: 1_523_456_789,
            bytes_up_mb: 1452.9,
            bytes_down_total: 9_876_543_210,
            bytes_down_mb: 9419.4
          },
          event_broker: %{
            enabled: true,
            enqueues_total: 1235,
            publishes_total: 1234,
            publishes_ok_total: 1230,
            publishes_error_total: 4
          },
          webhook: %{
            fan_outs_total: 1235,
            deliveries_total: 2470,
            deliveries_ok_total: 2400,
            deliveries_recoverable_total: 60,
            deliveries_terminal_total: 10
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
        },
        meta: EdgeAdminWeb.Schemas.CommonSchemas.MetaSchema
      },
      required: [:data, :meta]
    })
  end
end
