# edge_admin/lib/edge_admin/events/webhooks/forms/create_webhook_form.ex
defmodule EdgeAdmin.Events.Webhooks.Forms.CreateWebhookForm do
  @moduledoc """
  Form for validating webhook creation inputs.

  Validates external API inputs before handing off to the Webhook schema.
  Webhooks are immutable after create — there is no update form.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Events.Webhooks.Validators.WebhookValidators

  embedded_schema do
    field(:url, :string)
    field(:secret, :string)
    field(:headers, :map)
    field(:subscribed_events, {:array, :string})
  end

  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:url, :secret, :headers, :subscribed_events])
    |> validate_required([:url, :secret, :subscribed_events])
    |> validate_url()
    |> validate_secret()
    |> validate_headers()
    |> validate_subscribed_events()
    |> apply_action(:insert)
    |> case do
      {:ok, form} -> {:ok, to_map(form)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def changeset(_params) do
    changeset =
      %__MODULE__{}
      |> cast(%{}, [])
      |> add_error(:base, "invalid parameters - expected a map")

    {:error, %{changeset | action: :insert}}
  end

  defp validate_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        case WebhookValidators.url_error(url) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :url, message)
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
          {:error, message} -> add_error(changeset, :subscribed_events, message <> " — see /asyncdoc for the catalog")
        end
    end
  end

  defp to_map(%__MODULE__{} = form) do
    %{
      "url" => form.url,
      "secret" => form.secret,
      "headers" => form.headers,
      "subscribed_events" => form.subscribed_events
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
