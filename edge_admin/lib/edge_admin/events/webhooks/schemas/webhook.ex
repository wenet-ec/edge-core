# edge_admin/lib/edge_admin/events/webhooks/schemas/webhook.ex
defmodule EdgeAdmin.Events.Webhooks.Schemas.Webhook do
  @moduledoc "Ecto schema for a configured webhook delivery destination."
  use EdgeAdmin.Schema

  alias EdgeAdmin.Encryption.EncryptedBinary
  alias EdgeAdmin.Encryption.EncryptedMap
  alias EdgeAdmin.Events.Webhooks.Validators.WebhookValidators

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

      url ->
        case WebhookValidators.url_error(url) do
          :ok ->
            changeset

          {:error, "URL is not a valid absolute http(s) URL"} ->
            add_error(changeset, :url, "must be an absolute http(s) URL with a host")

          {:error, message} ->
            add_error(changeset, :url, message)
        end
    end
  end

  defp validate_secret(changeset) do
    case get_change(changeset, :secret) do
      nil ->
        changeset

      secret ->
        case WebhookValidators.secret_error(secret) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :secret, message)
        end
    end
  end

  defp validate_headers(changeset) do
    case get_change(changeset, :headers) do
      nil ->
        changeset

      headers ->
        case WebhookValidators.headers_error(headers) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :headers, message)
        end
    end
  end

  defp validate_subscribed_events(changeset) do
    case get_change(changeset, :subscribed_events) do
      nil ->
        changeset

      events ->
        case WebhookValidators.subscribed_events_error(events) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :subscribed_events, message)
        end
    end
  end
end
