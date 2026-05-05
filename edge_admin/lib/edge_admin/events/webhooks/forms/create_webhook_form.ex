# edge_admin/lib/edge_admin/events/webhooks/forms/create_webhook_form.ex
defmodule EdgeAdmin.Events.Webhooks.Forms.CreateWebhookForm do
  @moduledoc """
  Form for validating webhook creation inputs.

  Validates external API inputs before handing off to the Webhook schema.
  Webhooks are immutable after create — there is no update form.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks.Ssrf

  @max_events 20
  @min_secret_bytes 32

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
        case Ssrf.validate_url(url) do
          :ok -> changeset
          {:error, reason} -> add_error(changeset, :url, Ssrf.format_error(reason))
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

  defp validate_subscribed_events(changeset) do
    case get_change(changeset, :subscribed_events) do
      nil ->
        changeset

      [] ->
        add_error(changeset, :subscribed_events, "must include at least one event type")

      events when length(events) > @max_events ->
        add_error(changeset, :subscribed_events, "cannot exceed #{@max_events} events")

      events ->
        catalog = Catalog.all_event_types()
        unknown = Enum.reject(events, &(&1 in catalog))

        if unknown == [] do
          changeset
        else
          add_error(
            changeset,
            :subscribed_events,
            "unknown event type(s): #{Enum.join(unknown, ", ")} — see /asyncdoc for the catalog"
          )
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
