# edge_admin/lib/edge_admin/events/webhooks/forms/create_webhook_form.ex
defmodule EdgeAdmin.Events.Webhooks.Forms.CreateWebhookForm do
  @moduledoc """
  Form for validating webhook creation inputs.

  Validates external API inputs before handing off to the Webhook schema.
  Webhooks are immutable after create — there is no update form.
  """
  use EdgeAdmin.Form

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks.Limits
  alias EdgeAdmin.Events.Webhooks.Ssrf

  @max_url_length Limits.max_url_length()
  @min_secret_bytes Limits.min_secret_bytes()
  @max_secret_bytes Limits.max_secret_bytes()
  @max_headers Limits.max_headers()
  @max_header_value_length Limits.max_header_value_length()
  @min_subscribed_events Limits.min_subscribed_events()
  @max_subscribed_events Limits.max_subscribed_events()

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

      url when byte_size(url) > @max_url_length ->
        add_error(changeset, :url, "must be at most #{@max_url_length} characters")

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
