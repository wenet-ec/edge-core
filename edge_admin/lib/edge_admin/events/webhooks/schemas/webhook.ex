# edge_admin/lib/edge_admin/events/webhooks/schemas/webhook.ex
defmodule EdgeAdmin.Events.Webhooks.Schemas.Webhook do
  @moduledoc false
  use EdgeAdmin.Schema

  alias EdgeAdmin.Events.Webhooks.Filter
  alias EdgeAdmin.Vault.EncryptedBinary
  alias EdgeAdmin.Vault.EncryptedMap

  @type t :: %__MODULE__{
          id: String.t(),
          url: String.t(),
          secret: binary() | nil,
          headers: map() | nil,
          event_filters: [String.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
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
    field(:event_filters, {:array, :string})

    timestamps()
  end

  @max_filters 20
  @min_secret_bytes 32

  @doc false
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :secret, :headers, :event_filters])
    |> validate_required([:url, :secret, :event_filters])
    |> validate_url()
    |> validate_secret()
    |> validate_headers()
    |> validate_event_filters()
  end

  defp validate_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

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

      _ ->
        changeset
    end
  end

  defp validate_headers(changeset) do
    case get_change(changeset, :headers) do
      nil ->
        changeset

      headers when is_map(headers) ->
        bad =
          Enum.find(headers, fn {k, v} ->
            not (is_binary(k) and is_binary(v))
          end)

        if bad do
          add_error(changeset, :headers, "all keys and values must be strings")
        else
          changeset
        end

      _ ->
        add_error(changeset, :headers, "must be a map of string => string")
    end
  end

  defp validate_event_filters(changeset) do
    case get_change(changeset, :event_filters) do
      nil ->
        changeset

      [] ->
        add_error(changeset, :event_filters, "must include at least one pattern")

      patterns when length(patterns) > @max_filters ->
        add_error(changeset, :event_filters, "cannot exceed #{@max_filters} patterns")

      patterns ->
        Enum.reduce(patterns, changeset, fn pattern, acc ->
          case Filter.validate(pattern) do
            :ok -> acc
            {:error, reason} -> add_error(acc, :event_filters, "#{pattern}: #{reason}")
          end
        end)
    end
  end
end
