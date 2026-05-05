# edge_admin/lib/edge_admin_web/schemas/webhooks/webhook_schemas.ex
defmodule EdgeAdminWeb.Schemas.Webhooks.WebhookSchemas do
  @moduledoc """
  OpenAPI schemas for Webhook resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule WebhookResponse do
    @moduledoc false

    schema(%{
      title: "Webhook",
      description: """
      A webhook subscription. Receives a POST per matching event with the full
      CloudEvents envelope as the body and an HMAC-SHA256 signature in the
      `X-Edge-Signature` header.

      Webhooks are immutable after create — to change any field, delete and
      recreate. `secret` and `headers` are write-only — encrypted at rest and
      never appear in any response.
      """,
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique webhook identifier"
        },
        url: %Schema{
          type: :string,
          description: "Destination URL — receives a POST per matching event",
          example: "https://example.com/edge-events"
        },
        event_filters: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Wildcard patterns matched against envelope `type`. `*` matches any sequence of characters (including dots); `*` alone matches everything.",
          example: ["edge.node.*", "edge.command_execution.completed"]
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the webhook was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the webhook was last updated"
        }
      },
      required: [
        :id,
        :url,
        :event_filters,
        :inserted_at,
        :updated_at
      ],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        url: "https://example.com/edge-events",
        event_filters: ["edge.node.*", "edge.command_execution.completed"],
        inserted_at: "2026-05-05T10:00:00Z",
        updated_at: "2026-05-05T10:00:00Z"
      }
    })
  end

  defmodule WebhookPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        WebhookResponse,
        "WebhookPaginatedResponse",
        "Paginated list of webhooks with filtering and sorting metadata"
      )
    )
  end

  defmodule WebhookSingleResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        WebhookResponse,
        "WebhookSingleResponse",
        "Single webhook response"
      )
    )
  end

  defmodule WebhookCreateRequest do
    @moduledoc false

    schema(%{
      title: "WebhookCreateRequest",
      description: """
      Create a new webhook subscription. Webhooks are immutable after create —
      to change any field, delete and recreate.

      - `url` is SSRF-checked downstream. Loopback, RFC1918, link-local, and
        cloud-metadata IPs/hostnames are denied unless
        `WEBHOOK_ALLOW_PRIVATE_IPS=true` is set on the admin process.
      - `secret` is the HMAC-SHA256 signing key. Stays on the server; receivers
        verify the `X-Edge-Signature` header against their stored copy.
      - `headers` is an arbitrary string→string map stamped on every request
        (e.g. `Authorization: Bearer ...`). Up to 20 entries.
      - `event_filters` are wildcard patterns matched against envelope
        `type`. Each pattern must match at least one currently-known event
        type — typos are rejected at create time.

      Delivery retry budget is `WEBHOOK_MAX_ATTEMPTS` (default 3).

      Known event-type prefixes: `edge.node.*`, `edge.command_execution.*`,
      `edge.self_update_request.*`, `edge.enrollment_key.*`,
      `edge.ssh_username.*`. The full event catalog with payload schemas is
      documented in the [AsyncAPI spec](/asyncdoc).
      """,
      type: :object,
      properties: %{
        url: %Schema{
          type: :string,
          pattern: "^https?://.+",
          minLength: 1,
          maxLength: 2048,
          description: "Absolute http(s) URL. SSRF-checked downstream.",
          example: "https://example.com/edge-events"
        },
        secret: %Schema{
          type: :string,
          minLength: 32,
          maxLength: 256,
          description: "HMAC-SHA256 signing key (≥ 32 bytes). Never returned in responses.",
          example: "a-cryptographically-random-32-byte-secret"
        },
        headers: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string, maxLength: 4096},
          maxProperties: 20,
          description: "Extra HTTP headers. Up to 20 entries; each value up to 4096 characters.",
          example: %{"Authorization" => "Bearer xoxb-token", "X-Custom" => "value"}
        },
        event_filters: %Schema{
          type: :array,
          items: %Schema{
            type: :string,
            pattern: "^[a-z0-9_*]+(\\.[a-z0-9_*]+)*$",
            maxLength: 256
          },
          minItems: 1,
          maxItems: 20,
          description:
            "Wildcard patterns. `*` matches any sequence of characters (including dots); `*` alone matches everything. Each pattern must match at least one current event type.",
          example: ["edge.node.*", "edge.command_execution.completed"]
        }
      },
      required: [:url, :secret, :event_filters],
      example: %{
        url: "https://example.com/edge-events",
        secret: "a-cryptographically-random-32-byte-secret",
        headers: %{"Authorization" => "Bearer xoxb-token"},
        event_filters: ["edge.node.*", "edge.command_execution.completed"]
      }
    })
  end
end
