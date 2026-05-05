# edge_admin/lib/edge_admin_web/async_api_spec.ex
defmodule EdgeAdminWeb.AsyncApiSpec do
  @moduledoc """
  Builds the AsyncAPI 3.1.0 document describing all event broker messages
  published by Edge Admin.

  Served as JSON at `GET /api/asyncapi`.
  """

  @event_order [
    "edge.enrollment_key.verified",
    "edge.node.registered",
    "edge.node.reregistered",
    "edge.node.version_changed",
    "edge.node.status_changed",
    "edge.node.cluster_changed",
    "edge.node.update_triggered",
    "edge.command_execution.created",
    "edge.command_execution.sent",
    "edge.command_execution.completed",
    "edge.command_execution.cancelled",
    "edge.command_execution.expired",
    "edge.command_execution.pruned",
    "edge.ssh_username.verified",
    "edge.self_update_request.completed"
  ]

  @doc "Returns the AsyncAPI 3.1.0 document as a map (ready for Jason.encode!)."
  def spec do
    %{
      "asyncapi" => "3.1.0",
      "info" => %{
        "title" => "Edge Admin AsyncAPI",
        "version" => "0.2.0",
        "description" => """
        Lifecycle events published by Edge Admin to a configured message broker (NATS, Kafka/Redpanda, RabbitMQ, Redis, MQTT, AWS SNS, or Google Cloud Pub/Sub).

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

        **Webhook delivery:** every event in this spec is also deliverable via user-configured HTTP webhooks (always-on, no broker required). The same envelope is POSTed to each subscribed URL. Manage subscriptions via the REST `/api/v1/webhooks` endpoints — see the [Swagger UI](/swaggerui#/Events.Webhook) or [ReDoc](/redoc#tag/Events.Webhook).

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
          "Pub/sub mode works against any NATS server version — core PUB has been stable since NATS 1.x. " <>
            "JetStream mode requires NATS 2.2+ (released July 2021); the stream-create API and field shape we use are 2.2 baseline. " <>
            "Configure via EVENT_BROKER_NATS_URLS (comma-separated cluster list). " <>
            "Optional token auth via EVENT_BROKER_NATS_TOKEN. " <>
            "By default, pub/sub with no persistence. Set EVENT_BROKER_NATS_JETSTREAM=true to enable durable JetStream log — " <>
            "four streams are auto-created on startup: EDGE_NODES_EVENTS (captures edge.node.> + edge.enrollment_key.>), EDGE_COMMANDS_EVENTS, EDGE_SELF_UPDATES_EVENTS, EDGE_SSH_EVENTS. Retention is configured on the broker.",
        "security" => [%{"$ref" => "#/components/securitySchemes/natsToken"}]
      },
      "kafka" => %{
        "host" => "edge_event_broker_kafka:9092",
        "protocol" => "kafka",
        "title" => "Kafka / Redpanda",
        "summary" => "Any Kafka-compatible broker (Redpanda recommended — no JVM).",
        "description" =>
          "Redpanda is the recommended default — no JVM, lighter than vanilla Kafka. " <>
            "Compatible with Kafka 0.10+ (released Feb 2017) and any wire-compatible broker — " <>
            "brod auto-negotiates the per-API protocol version on connect. " <>
            "Configure via EVENT_BROKER_KAFKA_URLS (comma-separated `host:port` cluster list). " <>
            "SASL auth via EVENT_BROKER_KAFKA_USERNAME / EVENT_BROKER_KAFKA_PASSWORD / EVENT_BROKER_KAFKA_SASL_MECHANISM.",
        "security" => [%{"$ref" => "#/components/securitySchemes/kafkaSasl"}]
      },
      "rabbitmq" => %{
        "host" => "edge_event_broker_rabbitmq:5672",
        "protocol" => "amqp",
        "protocolVersion" => "0.9.1",
        "title" => "AMQP 0-9-1 (RabbitMQ-compatible)",
        "summary" => "AMQP 0-9-1 topic exchange; routing key = event type.",
        "description" =>
          "Adapter id: `amqp091` (alias: `rabbitmq`). Works against any AMQP 0-9-1 " <>
            "broker — RabbitMQ, LavinMQ, AmazonMQ for RabbitMQ, CloudAMQP. " <>
            "Configure via EVENT_BROKER_RABBITMQ_URL (single amqp:// or amqps:// URL). " <>
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
          "Compatible with Redis 2.0+ (Aug 2010, when Pub/Sub was introduced) and any wire-compatible server (Valkey, KeyDB, Dragonfly, etc.) — " <>
            "the adapter uses only `PING` and `PUBLISH` over RESP2. " <>
            "ACL usernames in URLs (`redis://user:pass@host`) and native TLS require Redis 6.0+ (Apr 2020); password-only URLs work against any version. " <>
            "Configure via EVENT_BROKER_REDIS_URL (single redis:// or rediss:// URL). " <>
            "Events are published via Redis Pub/Sub (`PUBLISH`). Channel = event type " <>
            "(e.g. `edge.node.registered`). Use `SUBSCRIBE` or `PSUBSCRIBE edge.*` to consume. " <>
            "No durability or replay. Credentials embedded in URL.",
        "security" => [%{"$ref" => "#/components/securitySchemes/redisAuth"}]
      },
      "mqtt" => %{
        "host" => "edge_event_broker_mqtt:1883",
        "protocol" => "mqtt",
        "title" => "MQTT",
        "summary" => "Any MQTT 3.1.1 or MQTT 5 broker. Configurable QoS, topic = event type with `/` separators.",
        "description" =>
          "Works against any MQTT broker (EMQX, Mosquitto, HiveMQ, AWS IoT Core, etc.). " <>
            "The publisher CONNECT uses MQTT 3.1.1 (`proto_ver: :v4`) as the lowest common denominator; " <>
            "v5 brokers downgrade our session to 3.1.1 transparently while operators run v5 freely on their subscribers. " <>
            "Configure via EVENT_BROKER_MQTT_URL (single host:port). " <>
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
      },
      "aws_sns" => %{
        "host" => "sns.us-east-1.amazonaws.com",
        "protocol" => "sns",
        "title" => "AWS SNS",
        "summary" => "AWS Simple Notification Service — managed fan-out pub/sub.",
        "description" =>
          "Managed AWS service; no on-prem broker. Four topics by domain: " <>
            "`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`, `edge-ssh-events` " <>
            "— must be pre-provisioned in your AWS account. Configure via " <>
            "EVENT_BROKER_AWS_SNS_REGION + EVENT_BROKER_AWS_SNS_TOPIC_ARN_PREFIX. " <>
            "Subscribers filter via subscription filter policies on message attributes " <>
            "(`type`, `corename`) — SNS has no topic-name wildcards. " <>
            "Durability is the subscriber's responsibility (typically SQS). " <>
            "Auth uses the standard AWS credential chain (IAM env vars, instance profile, etc.).",
        "security" => [%{"$ref" => "#/components/securitySchemes/awsSigV4"}]
      },
      "google_pubsub" => %{
        "host" => "pubsub.googleapis.com",
        "protocol" => "googlepubsub",
        "title" => "Google Cloud Pub/Sub",
        "summary" => "Google Cloud Pub/Sub — managed fan-out pub/sub.",
        "description" =>
          "Managed GCP service; no on-prem broker. Four topics by domain: " <>
            "`edge-nodes-events`, `edge-commands-events`, `edge-self-updates-events`, `edge-ssh-events` " <>
            "— must be pre-provisioned in your GCP project. Configure via " <>
            "EVENT_BROKER_GOOGLE_PUBSUB_PROJECT (+ optional EVENT_BROKER_GOOGLE_PUBSUB_TOPIC_ID_PREFIX). " <>
            "Subscribers filter via subscription filter expressions on message attributes " <>
            "(`type`, `corename`) — Pub/Sub has no topic-name wildcards. " <>
            "Durability is built in: each subscription buffers messages until ACKed " <>
            "(default 7-day retention, max 31). " <>
            "Auth uses the standard GCP credential chain — service-account JSON via " <>
            "GOOGLE_APPLICATION_CREDENTIALS, Workload Identity on GKE, or the GCE metadata server.",
        "security" => [%{"$ref" => "#/components/securitySchemes/googleOauth2"}]
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
    Enum.reduce(
      [
        enrollment_key_channels(),
        node_channels(),
        command_execution_channels(),
        ssh_username_channels(),
        self_update_request_channels()
      ],
      &Map.merge/2
    )
  end

  defp enrollment_key_channels do
    %{
      "edge.enrollment_key.verified" =>
        channel(
          "enrollment_key.verified",
          "enrollmentKeyVerifiedMessage",
          "Agent attempted to enroll using an enrollment key (success or failure)"
        )
    }
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
        channel("node.update_triggered", "nodeUpdateTriggeredMessage", "Self-update signal sent to this node")
    }
  end

  defp command_execution_channels do
    %{
      "edge.command_execution.created" =>
        channel("command_execution.created", "commandExecutionCreatedMessage", "Execution record created and queued"),
      "edge.command_execution.sent" =>
        channel("command_execution.sent", "commandExecutionSentMessage", "Execution delivered to agent and ACKed"),
      "edge.command_execution.completed" =>
        channel("command_execution.completed", "commandExecutionCompletedMessage", "Agent reported result"),
      "edge.command_execution.cancelled" =>
        channel(
          "command_execution.cancelled",
          "commandExecutionCancelledMessage",
          "Execution cancelled (explicit or SIGTERM)"
        ),
      "edge.command_execution.expired" =>
        channel(
          "command_execution.expired",
          "commandExecutionExpiredMessage",
          "Execution swept as stale before running"
        ),
      "edge.command_execution.pruned" =>
        channel(
          "command_execution.pruned",
          "commandExecutionPrunedMessage",
          "Execution reaped by background pruning worker"
        )
    }
  end

  defp ssh_username_channels do
    %{
      "edge.ssh_username.verified" =>
        channel(
          "ssh_username.verified",
          "sshUsernameVerifiedMessage",
          "Agent verified an SSH credential against admin (success or failure)"
        )
    }
  end

  defp self_update_request_channels do
    %{
      "edge.self_update_request.completed" =>
        channel("self_update_request.completed", "selfUpdateRequestCompletedMessage", "Self-update batch finished")
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
           },
           "sns" => sns_operation_binding(channel_id)
           # MQTT topic for each event is the channel address with `.` rewritten
           # to `/` (e.g. `edge.node.registered` → `edge/node/registered`) so MQTT
           # segment wildcards (`+`, `#`) work as expected. QoS shown above is the
           # default; configurable via EVENT_BROKER_MQTT_QOS.
           # SNS routes by topic ARN (one of four pre-provisioned domain topics:
           # edge-nodes-events, edge-commands-events, edge-self-updates-events,
           # edge-ssh-events) and by message attributes — `type` and `corename`
           # are promoted to attributes so subscription filter policies can
           # match without parsing the body. Google Cloud Pub/Sub routes the
           # same way; its bindings live on the channel + message objects (the
           # spec defines no operation-level bindings for googlepubsub).
         }
       }}
    end)
    |> Jason.OrderedObject.new()
  end

  defp sns_operation_binding(channel_id) do
    domain = sns_domain_for(channel_id)

    %{
      "topic" => %{
        "name" => "edge-#{domain}-events"
      },
      "consumers" => [
        %{
          "protocol" => "sqs",
          "endpoint" => %{
            "name" => "edge-#{domain}-events-debug"
          },
          "rawMessageDelivery" => true
        }
      ],
      "bindingVersion" => "0.1.0"
    }
  end

  defp sns_domain_for("edge.enrollment_key." <> _), do: "nodes"
  defp sns_domain_for("edge.node." <> _), do: "nodes"
  defp sns_domain_for("edge.command_execution." <> _), do: "commands"
  defp sns_domain_for("edge.ssh_username." <> _), do: "ssh"
  defp sns_domain_for("edge.self_update_request." <> _), do: "self-updates"

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
    "command_execution_id" => "cmdexec-abc123",
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
    "self_update_request_id" => "selfupd-abc123",
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
      # Enrollment key messages
      "enrollmentKeyVerifiedMessage" =>
        enrollment_key_message(
          "enrollment_key.verified",
          "EnrollmentKeyVerifiedEvent",
          "Agent attempted to enroll using an enrollment key",
          %{
            "enrollment_key_id" => "enrkey-abc123",
            "cluster_name" => "prod",
            "name" => "prod rollout",
            "uses_remaining" => 4,
            "result" => "verified",
            "verified_at" => "2026-04-13T10:00:00Z"
          }
        ),

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
          Map.put(@node_base_data, "self_update_request_id", "selfupd-abc123")
        ),

      # Command execution messages
      "commandExecutionCreatedMessage" =>
        command_execution_message(
          "command_execution.created",
          "CommandExecutionEvent",
          "Execution record created and queued",
          Map.merge(@execution_base_data, %{
            "status" => "pending",
            "exit_code" => nil,
            "sent_at" => nil,
            "completed_at" => nil,
            "cancelled_at" => nil
          })
        ),
      "commandExecutionSentMessage" =>
        command_execution_message(
          "command_execution.sent",
          "CommandExecutionEvent",
          "Execution delivered to agent and ACKed",
          Map.merge(@execution_base_data, %{
            "status" => "sent",
            "exit_code" => nil,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => nil,
            "cancelled_at" => nil
          })
        ),
      "commandExecutionCompletedMessage" =>
        command_execution_message(
          "command_execution.completed",
          "CommandExecutionEvent",
          "Agent reported result",
          Map.merge(@execution_base_data, %{
            "status" => "completed",
            "exit_code" => 0,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => "2026-04-13T10:00:03Z",
            "cancelled_at" => nil
          })
        ),
      "commandExecutionCancelledMessage" =>
        command_execution_message(
          "command_execution.cancelled",
          "CommandExecutionEvent",
          "Execution cancelled (explicit or SIGTERM)",
          Map.merge(@execution_base_data, %{
            "status" => "cancelled",
            "exit_code" => 143,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => nil,
            "cancelled_at" => "2026-04-13T10:00:05Z"
          })
        ),
      "commandExecutionExpiredMessage" =>
        command_execution_message(
          "command_execution.expired",
          "CommandExecutionEvent",
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
      "commandExecutionPrunedMessage" =>
        command_execution_message(
          "command_execution.pruned",
          "CommandExecutionEvent",
          "Execution reaped by background pruning worker",
          Map.merge(@execution_base_data, %{
            "status" => "completed",
            "exit_code" => 0,
            "sent_at" => "2026-04-13T10:00:01Z",
            "completed_at" => "2026-04-13T10:00:03Z",
            "cancelled_at" => nil
          })
        ),

      # SSH username messages
      "sshUsernameVerifiedMessage" =>
        ssh_username_message(
          "ssh_username.verified",
          "SshUsernameVerifiedEvent",
          "Agent verified an SSH credential against admin",
          %{
            "ssh_username_id" => "sshuser-abc123",
            "node_id" => "node-abc123",
            "cluster_name" => "prod",
            "username" => "deploy",
            "auth_method" => "public_key",
            "result" => "success",
            "verified_at" => "2026-04-13T10:00:00Z"
          }
        ),

      # Self-update request messages
      "selfUpdateRequestCompletedMessage" =>
        self_update_request_message(
          "self_update_request.completed",
          "SelfUpdateRequestEvent",
          "Self-update batch finished",
          Map.merge(@self_update_base_data, %{
            "status" => "completed",
            "summary" => %{"total" => 10, "triggered" => 9, "failed" => 1}
          })
        )
    }
  end

  defp enrollment_key_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "enrollment_key_id", data)
  end

  defp node_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "node_id", data)
  end

  defp command_execution_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "command_execution_id", data)
  end

  defp ssh_username_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "node_id", data)
  end

  defp self_update_request_message(event_type, schema_ref, summary, data) do
    build_message(event_type, schema_ref, summary, "self_update_request_id", data)
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
          # Per AsyncAPI's amqp binding spec: `contentEncoding` is a MIME
          # encoding (gzip/identity/etc), not a charset; `messageType` is an
          # application-specific type, not a MIME type. We're publishing JSON
          # bytes with no AMQP-specific application typing, so neither field
          # applies and we leave them unset. The Message Object's top-level
          # `contentType: application/json` covers MIME signaling.
          "bindingVersion" => "0.3.0"
        },
        "mqtt" => %{
          "payloadFormatIndicator" => 1,
          "contentType" => "application/json",
          "bindingVersion" => "0.2.0"
        },
        "googlepubsub" => %{
          # type + corename are promoted from envelope fields to message
          # attributes on every publish, so subscription filter expressions
          # like `hasPrefix(attributes.type, "edge.node.")` can route without
          # parsing the body. Body remains the full CloudEvents envelope.
          "attributes" => %{
            "type" => "string",
            "corename" => "string"
          },
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
    Enum.reduce(
      [
        envelope_schema(),
        enrollment_key_schema(),
        node_schemas(),
        command_execution_schema(),
        ssh_username_schema(),
        self_update_request_schema()
      ],
      &Map.merge/2
    )
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
              "edge.command_execution.created",
              "edge.command_execution.sent",
              "edge.command_execution.completed",
              "edge.command_execution.cancelled",
              "edge.command_execution.expired",
              "edge.command_execution.pruned",
              "edge.self_update_request.completed",
              "edge.enrollment_key.verified",
              "edge.ssh_username.verified"
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

  defp enrollment_key_schema do
    %{
      "EnrollmentKeyVerifiedEvent" => %{
        "type" => "object",
        "required" => ["result", "verified_at"],
        "description" =>
          "Agent presented an enrollment key to admin. The full key blob is " <>
            "intentionally excluded — it's a credential. On `:invalid_key`, " <>
            "`enrollment_key_id` and `cluster_name` are null (no DB row matched).",
        "properties" => %{
          "enrollment_key_id" => %{
            "type" => ["string", "null"],
            "format" => "uuid",
            "description" => "Null when result is invalid_key"
          },
          "cluster_name" => %{
            "type" => ["string", "null"],
            "description" => "Null when result is invalid_key"
          },
          "name" => %{
            "type" => ["string", "null"],
            "description" =>
              "Optional human-readable label for the key (display only). Null when unset or when result is invalid_key."
          },
          "uses_remaining" => %{
            "type" => ["integer", "null"],
            "description" => "Remaining uses after this attempt; null for unlimited keys or invalid_key"
          },
          "result" => %{
            "type" => "string",
            "enum" => ["verified", "invalid_key", "key_expired", "key_spent", "node_limit_reached"]
          },
          "verified_at" => %{"type" => "string", "format" => "date-time"}
        }
      }
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

  defp command_execution_schema do
    %{
      "CommandExecutionEvent" => %{
        "type" => "object",
        "required" => ["command_execution_id", "command_id", "node_id", "cluster_name", "status"],
        "description" => "`output` is excluded — fetch via API if needed",
        "properties" => %{
          "command_execution_id" => %{"type" => "string", "format" => "uuid"},
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

  defp ssh_username_schema do
    %{
      "SshUsernameVerifiedEvent" => %{
        "type" => "object",
        "required" => ["node_id", "username", "auth_method", "result", "verified_at"],
        "description" =>
          "Agent verified an SSH credential against admin. Password hashes and " <>
            "public-key strings are never echoed. `ssh_username_id` and " <>
            "`cluster_name` are null when no DB row matched the attempted " <>
            "(node_id, username) pair — failed attempts against missing usernames " <>
            "are still emitted as security signal.",
        "properties" => %{
          "ssh_username_id" => %{"type" => ["string", "null"], "format" => "uuid"},
          "node_id" => %{"type" => "string"},
          "cluster_name" => %{"type" => ["string", "null"]},
          "username" => %{"type" => "string", "description" => "The username the agent attempted to auth as"},
          "auth_method" => %{"type" => "string", "enum" => ["password", "public_key", "unknown"]},
          "result" => %{"type" => "string", "enum" => ["success", "failure"]},
          "verified_at" => %{"type" => "string", "format" => "date-time"}
        }
      }
    }
  end

  defp self_update_request_schema do
    %{
      "SelfUpdateRequestEvent" => %{
        "type" => "object",
        "required" => ["self_update_request_id", "status", "targeting"],
        "properties" => %{
          "self_update_request_id" => %{"type" => "string", "format" => "uuid"},
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
            "description" => "Populated on self_update_request.completed",
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
          "RabbitMQ credentials embedded in EVENT_BROKER_RABBITMQ_URL: amqp://user:pass@host:port. " <>
            "The amqp library parses them natively. Enable TLS with EVENT_BROKER_RABBITMQ_SSL=true."
      },
      "redisAuth" => %{
        "type" => "userPassword",
        "description" =>
          "Redis auth. Embed credentials in EVENT_BROKER_REDIS_URL: " <>
            "`redis://:password@host:port` (password-only) or " <>
            "`redis://username:password@host:port` (Redis 6+ ACL). " <>
            "Enable TLS with EVENT_BROKER_REDIS_SSL=true (use rediss:// URL for external brokers)."
      },
      "mqttAuth" => %{
        "type" => "userPassword",
        "description" =>
          "MQTT auth via EVENT_BROKER_MQTT_USERNAME + EVENT_BROKER_MQTT_PASSWORD, or EVENT_BROKER_MQTT_JWT. " <>
            "Enable TLS with EVENT_BROKER_MQTT_SSL=true. mTLS supported via cert file env vars."
      },
      "awsSigV4" => %{
        "type" => "httpApiKey",
        "name" => "Authorization",
        "in" => "header",
        "description" =>
          "AWS SigV4 request signing. Credentials resolved by ex_aws via the standard AWS credential " <>
            "chain: AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY env vars (with optional AWS_SESSION_TOKEN " <>
            "for STS / assumed roles), shared credentials file, or EC2/ECS/EKS instance metadata. " <>
            "AsyncAPI 3 has no first-class SigV4 type — modeled here as httpApiKey for documentation; " <>
            "the actual signing is handled by ex_aws."
      },
      "googleOauth2" => %{
        "type" => "oauth2",
        "flows" => %{
          "clientCredentials" => %{
            "tokenUrl" => "https://oauth2.googleapis.com/token",
            "availableScopes" => %{
              "https://www.googleapis.com/auth/pubsub" => "Publish to Pub/Sub topics"
            }
          }
        },
        "scopes" => ["https://www.googleapis.com/auth/pubsub"],
        "description" =>
          "Google Cloud Pub/Sub OAuth2 bearer tokens. Credentials resolved by goth via the standard GCP " <>
            "credential chain: GOOGLE_APPLICATION_CREDENTIALS service-account JSON, Workload Identity on GKE, " <>
            "or the GCE metadata server. The adapter requests tokens from goth on each publish; goth caches " <>
            "and refreshes them transparently."
      }
    }
  end
end
