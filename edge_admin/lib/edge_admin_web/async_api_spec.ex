# edge_admin/lib/edge_admin_web/async_api_spec.ex
defmodule EdgeAdminWeb.AsyncApiSpec do
  @moduledoc """
  Builds the AsyncAPI 3.1.0 document describing all event broker messages
  published by Edge Admin.

  Served as JSON at `GET /api/asyncapi`.
  """

  @event_order [
    "edge.node.registered",
    "edge.node.reregistered",
    "edge.node.version_changed",
    "edge.node.status_changed",
    "edge.node.cluster_changed",
    "edge.node.update_triggered",
    "edge.node.deleted",
    "edge.execution.created",
    "edge.execution.sent",
    "edge.execution.completed",
    "edge.execution.cancelled",
    "edge.execution.expired",
    "edge.self_update.created",
    "edge.self_update.completed"
  ]

  @doc "Returns the AsyncAPI 3.1.0 document as a map (ready for Jason.encode!)."
  def spec do
    %{
      "asyncapi" => "3.1.0",
      "info" => %{
        "title" => "Edge Admin AsyncAPI",
        "version" => "0.2.0",
        "description" => """
        Lifecycle events published by Edge Admin to a configured message broker (NATS, Kafka/Redpanda, RabbitMQ, or Redis).

        Edge Admin publishes and forgets — it has no knowledge of consumers.
        All messages follow the [CloudEvents 1.0](https://cloudevents.io) spec.
        `corename` is a CloudEvents extension attribute identifying the publishing Edge Admin instance.

        ```json
        {
          "specversion": "1.0",
          "id": "<uuid v4>",
          "source": "https://github.com/wenet-ec/edge-core",
          "type": "edge.node.registered",
          "time": "2026-04-13T10:00:00Z",
          "datacontenttype": "application/json",
          "corename": "prod-us",
          "data": { ... }
        }
        ```

        Enable publishing by setting `EVENT_BROKER_ENABLED=true` on the admin.

        **Explore:**
        - [AsyncAPI viewer](/asyncdoc) — this page
        - [Raw spec](/api/asyncapi) — AsyncAPI JSON

        **REST API:** See the [Swagger UI](/swaggerui), [ReDoc](/redoc), or [download the OpenAPI spec](/api/openapi).
        """
      },
      "defaultContentType" => "application/json",
      "servers" => servers(),
      "channels" => channels(),
      "operations" => operations(),
      "components" => components()
    }
  end

  # ---------------------------------------------------------------------------
  # Servers
  # ---------------------------------------------------------------------------

  defp servers do
    %{
      "nats" => %{
        "host" => "edge_event_broker_nats:4222",
        "protocol" => "nats",
        "title" => "NATS",
        "summary" => "Pub/sub by default; JetStream for durable log + replay.",
        "description" =>
          "Configure via EVENT_BROKER_URLS. Optional token auth via EVENT_BROKER_NATS_TOKEN. " <>
            "By default, pub/sub with no persistence. Set EVENT_BROKER_NATS_JETSTREAM=true to enable durable JetStream log — " <>
            "three streams are auto-created on startup: EDGE_NODE_EVENTS, EDGE_EXECUTION_EVENTS, EDGE_SELF_UPDATE_EVENTS. Retention is configured on the broker.",
        "security" => [%{"$ref" => "#/components/securitySchemes/natsToken"}]
      },
      "kafka" => %{
        "host" => "edge_event_broker_kafka:9092",
        "protocol" => "kafka",
        "title" => "Kafka / Redpanda",
        "summary" => "Any Kafka-compatible broker (Redpanda recommended — no JVM).",
        "description" =>
          "Redpanda is the recommended default — no JVM, lighter than vanilla Kafka. " <>
            "Configure via EVENT_BROKER_URLS (host:port, comma-separated). " <>
            "SASL auth via EVENT_BROKER_KAFKA_USERNAME / EVENT_BROKER_KAFKA_PASSWORD / EVENT_BROKER_KAFKA_SASL_MECHANISM.",
        "security" => [%{"$ref" => "#/components/securitySchemes/kafkaSasl"}]
      },
      "rabbitmq" => %{
        "host" => "edge_event_broker_rabbitmq:5672",
        "protocol" => "amqp",
        "title" => "RabbitMQ",
        "summary" => "AMQP topic exchange; routing key = event type.",
        "description" =>
          "Configure via EVENT_BROKER_URLS (single amqp:// or amqps:// URL). " <>
            "All events are published to a durable topic exchange `edge.events`. " <>
            "Routing key = event type (e.g. `edge.node.registered`). " <>
            "Consumer queue durability is the consumer's choice.",
        "security" => [%{"$ref" => "#/components/securitySchemes/amqpPlain"}]
      },
      "redis" => %{
        "host" => "edge_event_broker_redis:6379",
        "protocol" => "redis",
        "title" => "Redis",
        "summary" => "Pure pub/sub (`PUBLISH`/`SUBSCRIBE`). Fire-and-forget.",
        "description" =>
          "Configure via EVENT_BROKER_URLS (single redis:// or rediss:// URL). " <>
            "Events are published via Redis Pub/Sub (`PUBLISH`). Channel = event type " <>
            "(e.g. `edge.node.registered`). Use `SUBSCRIBE` or `PSUBSCRIBE edge.*` to consume. " <>
            "No durability or replay. Credentials embedded in URL.",
        "security" => [%{"$ref" => "#/components/securitySchemes/redisAuth"}]
      },
      "mqtt" => %{
        "host" => "edge_event_broker_mqtt:1883",
        "protocol" => "mqtt",
        "title" => "MQTT",
        "summary" => "Any MQTT 3.1.1 / 5 broker. Configurable QoS, topic = event type with `/` separators.",
        "description" =>
          "Works against any MQTT broker (EMQX, Mosquitto, HiveMQ, AWS IoT Core, etc.). " <>
            "Configure via EVENT_BROKER_URLS (host:port, only the first URL is used). " <>
            "Topic = event type with `.` rewritten to `/` (e.g. `edge/node/registered`). " <>
            "Subscribers use MQTT wildcards: `edge/#`, `edge/node/+`, etc. " <>
            "Default publish QoS is 1; configurable via EVENT_BROKER_MQTT_QOS=0|1|2.",
        "security" => [%{"$ref" => "#/components/securitySchemes/mqttAuth"}],
        "bindings" => %{
          "mqtt" => %{
            "clientId" => "edge_admin-<node>-<unique>",
            "cleanSession" => true,
            "keepAlive" => 60,
            "bindingVersion" => "0.2.0"
          }
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Channels — one per subject/topic
  # ---------------------------------------------------------------------------

  defp channels do
    @event_order
    |> Enum.map(fn channel_id -> {channel_id, Map.fetch!(raw_channels(), channel_id)} end)
    |> Jason.OrderedObject.new()
  end

  defp raw_channels do
    Map.merge(node_channels(), Map.merge(execution_channels(), self_update_channels()))
  end

  defp node_channels do
    %{
      "edge.node.registered" =>
        channel("node.registered", "nodeRegisteredMessage", "Node registered for the first time"),
      "edge.node.reregistered" =>
        channel("node.reregistered", "nodeReregisteredMessage", "Node re-enrolled (reboot, redeploy, etc.)"),
      "edge.node.version_changed" =>
        channel("node.version_changed", "nodeVersionChangedMessage", "Node version changed alongside re-enrollment"),
      "edge.node.status_changed" =>
        channel("node.status_changed", "nodeStatusChangedMessage", "Node health status transitioned"),
      "edge.node.cluster_changed" =>
        channel("node.cluster_changed", "nodeClusterChangedMessage", "Node moved to a different cluster"),
      "edge.node.update_triggered" =>
        channel("node.update_triggered", "nodeUpdateTriggeredMessage", "Self-update signal sent to this node"),
      "edge.node.deleted" => channel("node.deleted", "nodeDeletedMessage", "Node removed from the system")
    }
  end

  defp execution_channels do
    %{
      "edge.execution.created" =>
        channel("execution.created", "executionCreatedMessage", "Execution record created and queued"),
      "edge.execution.sent" =>
        channel("execution.sent", "executionSentMessage", "Execution delivered to agent and ACKed"),
      "edge.execution.completed" =>
        channel("execution.completed", "executionCompletedMessage", "Agent reported result"),
      "edge.execution.cancelled" =>
        channel("execution.cancelled", "executionCancelledMessage", "Execution cancelled (explicit or SIGTERM)"),
      "edge.execution.expired" =>
        channel("execution.expired", "executionExpiredMessage", "Execution swept as stale before running")
    }
  end

  defp self_update_channels do
    %{
      "edge.self_update.created" =>
        channel("self_update.created", "selfUpdateCreatedMessage", "Self-update request created"),
      "edge.self_update.completed" =>
        channel("self_update.completed", "selfUpdateCompletedMessage", "Self-update batch finished")
    }
  end

  defp channel(event_type, message_ref, description) do
    %{
      "address" => "edge.#{event_type}",
      "description" => description,
      "messages" => %{
        event_type => %{"$ref" => "#/components/messages/#{message_ref}"}
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Operations — one send operation per channel
  # ---------------------------------------------------------------------------

  defp operations do
    @event_order
    |> Enum.map(fn channel_id ->
      operation_id = "publish_#{String.replace(channel_id, ~r/[.\-]/, "_")}"

      {operation_id,
       %{
         "action" => "send",
         "channel" => %{"$ref" => "#/channels/#{channel_id}"},
         "bindings" => %{
           "nats" => %{"bindingVersion" => "0.1.0"},
           "kafka" => %{"bindingVersion" => "0.5.0"},
           "amqp" => %{
             "bindingVersion" => "0.3.0",
             "deliveryMode" => 2
           },
           "redis" => %{"bindingVersion" => "0.1.0"},
           "mqtt" => %{
             "qos" => 1,
             "retain" => false,
             "bindingVersion" => "0.2.0"
           }
           # Note: MQTT topic for each event is the channel address with `.` rewritten
           # to `/` (e.g. `edge.node.registered` → `edge/node/registered`) so MQTT
           # segment wildcards (`+`, `#`) work as expected. QoS shown above is the
           # default; configurable via EVENT_BROKER_MQTT_QOS.
         }
       }}
    end)
    |> Jason.OrderedObject.new()
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp components do
    %{
      "messages" => messages(),
      "schemas" => schemas(),
      "securitySchemes" => security_schemes()
    }
  end

  # ---------------------------------------------------------------------------
  # Messages — one per event type, each with its own example
  # ---------------------------------------------------------------------------

  @node_base_data %{
    "node_id" => "node-abc123",
    "cluster_name" => "prod",
    "status" => "healthy",
    "version" => "1.2.0",
    "id_type" => "hostname",
    "http_port" => 44_000,
    "ssh_port" => 40_022,
    "host_metrics_port" => 9100,
    "wireguard_metrics_port" => 9101,
    "http_proxy_port" => 44_001,
    "socks5_proxy_port" => 44_002,
    "self_update_enabled" => true,
    "last_seen_at" => "2026-04-13T10:00:00Z",
    "inserted_at" => "2026-04-13T09:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  @execution_base_data %{
    "execution_id" => "exec-abc123",
    "command_id" => "cmd-xyz789",
    "node_id" => "node-abc123",
    "cluster_name" => "prod",
    "command_text" => "systemctl restart app",
    "timeout" => 30_000,
    "target_all" => false,
    "expired_at" => nil,
    "inserted_at" => "2026-04-13T10:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  @self_update_base_data %{
    "request_id" => "req-abc123",
    "targeting" => %{
      "type" => "clusters",
      "cluster_filters" => %{},
      "node_filters" => %{"version" => "1.1.*"}
    },
    "inserted_at" => "2026-04-13T10:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  defp messages do
    %{
      # Node messages
      "nodeRegisteredMessage" =>
        node_message("node.registered", "NodeEvent", "Node registered for the first time", @node_base_data),
      "nodeReregisteredMessage" =>
        node_message(
          "node.reregistered",
          "NodeEvent",
          "Node re-enrolled (reboot, redeploy, etc.)",
          Map.put(@node_base_data, "status", "healthy")
        ),
      "nodeVersionChangedMessage" =>
        node_message(
          "node.version_changed",
          "NodeVersionChangedEvent",
          "Node version changed alongside re-enrollment",
          Map.put(@node_base_data, "previous_version", "1.1.0")
        ),
      "nodeStatusChangedMessage" =>
        node_message(
          "node.status_changed",
          "NodeStatusChangedEvent",
          "Node health status transitioned",
          Map.merge(@node_base_data, %{"status" => "unhealthy", "previous_status" => "healthy"})
        ),
      "nodeClusterChangedMessage" =>
        node_message(
          "node.cluster_changed",
          "NodeClusterChangedEvent",
          "Node moved to a different cluster",
          Map.put(@node_base_data, "previous_cluster_name", "staging")
        ),
      "nodeUpdateTriggeredMessage" =>
        node_message(
          "node.update_triggered",
          "NodeUpdateTriggeredEvent",
          "Self-update signal sent to this node",
          Map.put(@node_base_data, "self_update_request_id", "req-abc123")
        ),
      "nodeDeletedMessage" =>
        node_message("node.deleted", "NodeEvent", "Node removed from the system", @node_base_data),

      # Execution messages
      "executionCreatedMessage" =>
        execution_message(
          "execution.created",
          "ExecutionEvent",
          "Execution record created and queued",
          Map.merge(@execution_base_data, %{
            "status" => "pending",
            "exit_code" => nil,
            "sent_at" => nil,
            "completed_at" => nil,
            "cancelled_at" => nil
          })
        ),
      "executionSentMessage" =>
        execution_message(
          "execution.sent",
          "ExecutionEvent",
          "Execution delivered to agent and ACKed",
          Map.merge(@execution_base_data, %{
            "status" => "sent",
            "exit_code" => nil,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => nil,
            "cancelled_at" => nil
          })
        ),
      "executionCompletedMessage" =>
        execution_message(
          "execution.completed",
          "ExecutionEvent",
          "Agent reported result",
          Map.merge(@execution_base_data, %{
            "status" => "completed",
            "exit_code" => 0,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => "2026-04-13T10:00:03Z",
            "cancelled_at" => nil
          })
        ),
      "executionCancelledMessage" =>
        execution_message(
          "execution.cancelled",
          "ExecutionEvent",
          "Execution cancelled (explicit or SIGTERM)",
          Map.merge(@execution_base_data, %{
            "status" => "cancelled",
            "exit_code" => 143,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => nil,
            "cancelled_at" => "2026-04-13T10:00:05Z"
          })
        ),
      "executionExpiredMessage" =>
        execution_message(
          "execution.expired",
          "ExecutionEvent",
          "Execution swept as stale before running",
          Map.merge(@execution_base_data, %{
            "status" => "expired",
            "exit_code" => nil,
            "sent_at" => nil,
            "completed_at" => nil,
            "cancelled_at" => nil,
            "expired_at" => "2026-04-13T10:05:00Z"
          })
        ),

      # Self-update messages
      "selfUpdateCreatedMessage" =>
        self_update_message(
          "self_update.created",
          "SelfUpdateEvent",
          "Self-update request created",
          Map.merge(@self_update_base_data, %{"status" => "pending", "summary" => nil})
        ),
      "selfUpdateCompletedMessage" =>
        self_update_message(
          "self_update.completed",
          "SelfUpdateEvent",
          "Self-update batch finished",
          Map.merge(@self_update_base_data, %{
            "status" => "completed",
            "summary" => %{"total" => 10, "triggered" => 9, "failed" => 1}
          })
        )
    }
  end

  defp node_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "node_id", data)
  end

  defp execution_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "command_id", data)
  end

  defp self_update_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "request_id", data)
  end

  defp build_message(event_type, _schema_ref, summary, kafka_partition_key, data) do
    %{
      "summary" => summary,
      "contentType" => "application/json",
      "payload" => %{"$ref" => "#/components/schemas/Envelope"},
      "bindings" => %{
        "kafka" => %{
          "key" => %{
            "type" => "string",
            "description" => "Kafka partition key — `#{kafka_partition_key}` from the event data"
          },
          "bindingVersion" => "0.5.0"
        },
        "amqp" => %{
          "bindingVersion" => "0.3.0",
          "contentEncoding" => "UTF-8",
          "messageType" => "application/json"
        },
        "mqtt" => %{
          "payloadFormatIndicator" => 1,
          "contentType" => "application/json",
          "bindingVersion" => "0.2.0"
        }
      },
      "examples" => [
        %{
          "name" => "example",
          "payload" => %{
            "specversion" => "1.0",
            "id" => "550e8400-e29b-41d4-a716-446655440000",
            "source" => "https://github.com/wenet-ec/edge-core",
            "type" => event_type,
            "time" => "2026-04-13T10:00:00Z",
            "datacontenttype" => "application/json",
            "corename" => "prod-us",
            "data" => data
          }
        }
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # Schemas
  # ---------------------------------------------------------------------------

  defp schemas do
    Map.merge(envelope_schema(), Map.merge(node_schemas(), Map.merge(execution_schema(), self_update_schema())))
  end

  defp envelope_schema do
    %{
      "Envelope" => %{
        "type" => "object",
        "required" => ["specversion", "id", "source", "type", "time", "datacontenttype", "data"],
        "properties" => %{
          "specversion" => %{
            "type" => "string",
            "enum" => ["1.0"]
          },
          "id" => %{
            "type" => "string",
            "format" => "uuid",
            "description" =>
              "Unique per publish. Useful for broker-retry dedup. Not a dedup key for edge.node.status_changed duplicates — use (node_id, previous_status, status, time) for that."
          },
          "source" => %{
            "type" => "string",
            "const" => "https://github.com/wenet-ec/edge-core"
          },
          "type" => %{
            "type" => "string",
            "enum" => [
              "edge.node.registered",
              "edge.node.reregistered",
              "edge.node.version_changed",
              "edge.node.status_changed",
              "edge.node.cluster_changed",
              "edge.node.update_triggered",
              "edge.node.deleted",
              "edge.execution.created",
              "edge.execution.sent",
              "edge.execution.completed",
              "edge.execution.cancelled",
              "edge.execution.expired",
              "edge.self_update.created",
              "edge.self_update.completed"
            ]
          },
          "time" => %{
            "type" => "string",
            "format" => "date-time",
            "description" => "When the state change happened in admin"
          },
          "datacontenttype" => %{
            "type" => "string",
            "const" => "application/json"
          },
          "corename" => %{
            "type" => "string",
            "description" =>
              "Identifies the publishing core instance. Defaults to \"default\". Set via CORE_NAME env var."
          },
          "data" => %{"type" => "object"}
        }
      }
    }
  end

  defp node_base_properties do
    %{
      "node_id" => %{"type" => "string"},
      "cluster_name" => %{"type" => "string"},
      "status" => %{"type" => "string", "enum" => ["healthy", "unhealthy", "unreachable"]},
      "version" => %{"type" => "string"},
      "id_type" => %{"type" => "string"},
      "http_port" => %{"type" => "integer"},
      "ssh_port" => %{"type" => "integer"},
      "host_metrics_port" => %{"type" => "integer"},
      "wireguard_metrics_port" => %{"type" => "integer"},
      "http_proxy_port" => %{"type" => "integer"},
      "socks5_proxy_port" => %{"type" => "integer"},
      "self_update_enabled" => %{"type" => "boolean"},
      "last_seen_at" => %{"type" => ["string", "null"], "format" => "date-time"},
      "inserted_at" => %{"type" => "string", "format" => "date-time"},
      "updated_at" => %{"type" => "string", "format" => "date-time"}
    }
  end

  defp node_schemas do
    %{
      "NodeEvent" => %{
        "type" => "object",
        "required" => ["node_id", "cluster_name", "status"],
        "properties" => node_base_properties()
      },
      "NodeVersionChangedEvent" => %{
        "type" => "object",
        "required" => ["node_id", "cluster_name", "status", "previous_version"],
        "properties" =>
          Map.put(node_base_properties(), "previous_version", %{
            "type" => "string",
            "description" => "Version before this re-enrollment"
          })
      },
      "NodeStatusChangedEvent" => %{
        "type" => "object",
        "required" => ["node_id", "cluster_name", "status", "previous_status"],
        "properties" =>
          Map.put(node_base_properties(), "previous_status", %{
            "type" => "string",
            "enum" => ["healthy", "unhealthy", "unreachable"],
            "description" => "Status before this transition"
          })
      },
      "NodeClusterChangedEvent" => %{
        "type" => "object",
        "required" => ["node_id", "cluster_name", "status", "previous_cluster_name"],
        "properties" =>
          Map.put(node_base_properties(), "previous_cluster_name", %{
            "type" => "string",
            "description" => "Cluster before this move"
          })
      },
      "NodeUpdateTriggeredEvent" => %{
        "type" => "object",
        "required" => ["node_id", "cluster_name", "status", "self_update_request_id"],
        "properties" =>
          Map.put(node_base_properties(), "self_update_request_id", %{
            "type" => "string",
            "format" => "uuid",
            "description" => "The self-update request that triggered this"
          })
      }
    }
  end

  defp execution_schema do
    %{
      "ExecutionEvent" => %{
        "type" => "object",
        "required" => ["execution_id", "command_id", "node_id", "cluster_name", "status"],
        "description" => "`output` is excluded — fetch via API if needed",
        "properties" => %{
          "execution_id" => %{"type" => "string", "format" => "uuid"},
          "command_id" => %{"type" => "string", "format" => "uuid"},
          "node_id" => %{"type" => "string"},
          "cluster_name" => %{"type" => "string"},
          "command_text" => %{"type" => "string"},
          "timeout" => %{"type" => ["integer", "null"]},
          "status" => %{"type" => "string", "enum" => ["pending", "sent", "completed", "cancelled", "expired"]},
          "exit_code" => %{
            "type" => ["integer", "null"],
            "description" => "null until completed or cancelled; 143 on SIGTERM cancel"
          },
          "target_all" => %{"type" => "boolean"},
          "expired_at" => %{"type" => ["string", "null"], "format" => "date-time"},
          "sent_at" => %{"type" => ["string", "null"], "format" => "date-time"},
          "completed_at" => %{"type" => ["string", "null"], "format" => "date-time"},
          "cancelled_at" => %{"type" => ["string", "null"], "format" => "date-time"},
          "inserted_at" => %{"type" => "string", "format" => "date-time"},
          "updated_at" => %{"type" => "string", "format" => "date-time"}
        }
      }
    }
  end

  defp self_update_schema do
    %{
      "SelfUpdateEvent" => %{
        "type" => "object",
        "required" => ["request_id", "status", "targeting"],
        "properties" => %{
          "request_id" => %{"type" => "string", "format" => "uuid"},
          "status" => %{"type" => "string", "enum" => ["pending", "processing", "completed"]},
          "targeting" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string", "enum" => ["all", "nodes", "clusters"]},
              "cluster_filters" => %{"type" => "object"},
              "node_filters" => %{"type" => "object"}
            }
          },
          "summary" => %{
            "description" => "null on self_update.created; populated on self_update.completed",
            "oneOf" => [
              %{
                "type" => "object",
                "properties" => %{
                  "total" => %{"type" => "integer"},
                  "triggered" => %{"type" => "integer"},
                  "failed" => %{"type" => "integer"}
                }
              },
              %{"type" => "null"}
            ]
          },
          "inserted_at" => %{"type" => "string", "format" => "date-time"},
          "updated_at" => %{"type" => "string", "format" => "date-time"}
        }
      }
    }
  end

  defp security_schemes do
    %{
      "natsToken" => %{
        "type" => "http",
        "scheme" => "bearer",
        "description" => "NATS token auth. Set via EVENT_BROKER_NATS_TOKEN."
      },
      "kafkaSasl" => %{
        "type" => "scramSha256",
        "description" =>
          "Kafka SASL auth via EVENT_BROKER_KAFKA_USERNAME + EVENT_BROKER_KAFKA_PASSWORD. " <>
            "Mechanism configurable: EVENT_BROKER_KAFKA_SASL_MECHANISM=plain|scram_sha_256|scram_sha_512. " <>
            "Enable TLS with EVENT_BROKER_KAFKA_SSL=true."
      },
      "amqpPlain" => %{
        "type" => "userPassword",
        "description" =>
          "RabbitMQ credentials embedded in EVENT_BROKER_URLS: amqp://user:pass@host:port. " <>
            "The amqp library parses them natively. Enable TLS with EVENT_BROKER_RABBITMQ_SSL=true."
      },
      "redisAuth" => %{
        "type" => "userPassword",
        "description" =>
          "Redis auth. Embed credentials in EVENT_BROKER_URLS: " <>
            "`redis://:password@host:port` (password-only) or " <>
            "`redis://username:password@host:port` (Redis 6+ ACL). " <>
            "Enable TLS with EVENT_BROKER_REDIS_SSL=true (use rediss:// URL for external brokers)."
      },
      "mqttAuth" => %{
        "type" => "userPassword",
        "description" =>
          "MQTT auth via EVENT_BROKER_MQTT_USERNAME + EVENT_BROKER_MQTT_PASSWORD, or EVENT_BROKER_MQTT_JWT. " <>
            "Enable TLS with EVENT_BROKER_MQTT_SSL=true. mTLS supported via cert file env vars."
      }
    }
  end
end
