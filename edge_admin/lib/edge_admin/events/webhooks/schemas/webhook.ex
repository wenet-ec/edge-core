# edge_admin/lib/edge_admin/events/webhooks/schemas/webhook.ex
defmodule EdgeAdmin.Events.Webhooks.Schemas.Webhook do
  @moduledoc "Ecto schema for a configured webhook delivery destination."
  use EdgeAdmin.Schema

  alias EdgeAdmin.Encryption.EncryptedBinary
  alias EdgeAdmin.Encryption.EncryptedMap
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks.Limits

  @type t :: %__MODULE__{
          id: String.t() | nil,
          url: String.t() | nil,
          secret: binary() | nil,
          headers: map() | nil,
          subscribed_events: [String.t()] | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {
    Flop.Schema,
    filterable: [:url, :inserted_at, :updated_at],
    sortable: [:url, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "webhooks" do
    field(:url, :string)
    field(:secret, EncryptedBinary, redact: true)
    field(:headers, EncryptedMap, redact: true)
    field(:subscribed_events, {:array, :string})

    timestamps()
  end

  @max_url_length Limits.max_url_length()
  @min_secret_bytes Limits.min_secret_bytes()
  @max_secret_bytes Limits.max_secret_bytes()
  @max_headers Limits.max_headers()
  @max_header_value_length Limits.max_header_value_length()
  @min_subscribed_events Limits.min_subscribed_events()
  @max_subscribed_events Limits.max_subscribed_events()

  @doc "Builds a changeset for creating or updating a webhook."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :secret, :headers, :subscribed_events])
    |> validate_required([:url, :secret, :subscribed_events])
    |> validate_url()
    |> validate_secret()
    |> validate_headers()
    |> validate_subscribed_events()
  end

  defp validate_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url when byte_size(url) > @max_url_length ->
        add_error(changeset, :url, "must be at most #{@max_url_length} characters")

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            changeset

          _ ->
            add_error(changeset, :url, "must be an absolute http(s) URL with a host")
        end
    end
  end

  defp validate_secret(changeset) do
    case get_change(changeset, :secret) do
      nil ->
        changeset

      secret when is_binary(secret) and byte_size(secret) < @min_secret_bytes ->
        add_error(changeset, :secret, "must be at least #{@min_secret_bytes} bytes")

      secret when is_binary(secret) and byte_size(secret) > @max_secret_bytes ->
        add_error(changeset, :secret, "must be at most #{@max_secret_bytes} bytes")

      _ ->
        changeset
    end
  end

  defp validate_headers(changeset) do
    case get_change(changeset, :headers) do
      nil ->
        changeset

      headers when is_map(headers) ->
        cond do
          map_size(headers) > @max_headers ->
            add_error(changeset, :headers, "must have at most #{@max_headers} entries")

          not Enum.all?(headers, fn {k, v} -> is_binary(k) and is_binary(v) end) ->
            add_error(changeset, :headers, "all keys and values must be strings")

          oversized_header_value?(headers) ->
            add_error(
              changeset,
              :headers,
              "each header value must be at most #{@max_header_value_length} characters"
            )

          true ->
            changeset
        end

      _ ->
        add_error(changeset, :headers, "must be a map of string => string")
    end
  end

  defp oversized_header_value?(headers) do
    Enum.any?(headers, fn {_k, v} -> is_binary(v) and String.length(v) > @max_header_value_length end)
  end

  defp validate_subscribed_events(changeset) do
    case get_change(changeset, :subscribed_events) do
      nil ->
        changeset

      events when length(events) < @min_subscribed_events ->
        add_error(changeset, :subscribed_events, "must include at least one event type")

      events when length(events) > @max_subscribed_events ->
        add_error(changeset, :subscribed_events, "cannot exceed #{@max_subscribed_events} events")

      events ->
        catalog = Catalog.all_event_types()
        unknown = Enum.reject(events, &(&1 in catalog))

        if unknown == [] do
          changeset
        else
          add_error(
            changeset,
            :subscribed_events,
            "unknown event type(s): #{Enum.join(unknown, ", ")}"
          )
        end
    end
  end
end
