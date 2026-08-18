# edge_admin/lib/edge_admin/events/webhooks/validators/webhook_validators.ex
defmodule EdgeAdmin.Events.Webhooks.Validators.WebhookValidators do
  @moduledoc "Pure value-level validators for webhook configuration."

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks.Limits

  @spec url_error(term()) :: :ok | {:error, String.t()}
  def url_error(url) when is_binary(url) do
    if byte_size(url) > Limits.max_url_length() do
      {:error, "must be at most #{Limits.max_url_length()} characters"}
    else
      case URI.parse(url) do
        %URI{scheme: scheme, host: host, userinfo: nil, fragment: nil}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          :ok

        %URI{userinfo: userinfo} when not is_nil(userinfo) ->
          {:error, "URL must not include userinfo (user:pass@host)"}

        %URI{fragment: fragment} when not is_nil(fragment) ->
          {:error, "URL must not include a fragment"}

        _ ->
          {:error, "URL is not a valid absolute http(s) URL"}
      end
    end
  end

  def url_error(_url), do: {:error, "URL is not a valid absolute http(s) URL"}

  @spec secret_error(term()) :: :ok | {:error, String.t()}
  def secret_error(secret) when is_binary(secret) do
    cond do
      byte_size(secret) < Limits.min_secret_bytes() -> {:error, "must be at least #{Limits.min_secret_bytes()} bytes"}
      byte_size(secret) > Limits.max_secret_bytes() -> {:error, "must be at most #{Limits.max_secret_bytes()} bytes"}
      true -> :ok
    end
  end

  def secret_error(_secret), do: :ok

  @spec headers_error(term()) :: :ok | {:error, String.t()}
  def headers_error(headers) when is_map(headers) do
    cond do
      map_size(headers) > Limits.max_headers() ->
        {:error, "must have at most #{Limits.max_headers()} entries"}

      not Enum.all?(headers, fn {key, value} -> is_binary(key) and is_binary(value) end) ->
        {:error, "all keys and values must be strings"}

      Enum.any?(headers, fn {_key, value} -> String.length(value) > Limits.max_header_value_length() end) ->
        {:error, "each header value must be at most #{Limits.max_header_value_length()} characters"}

      true ->
        :ok
    end
  end

  def headers_error(_headers), do: {:error, "must be a map of string => string"}

  @spec subscribed_events_error(term()) :: :ok | {:error, String.t()}
  def subscribed_events_error(events) when is_list(events) do
    cond do
      length(events) < Limits.min_subscribed_events() ->
        {:error, "must include at least one event type"}

      length(events) > Limits.max_subscribed_events() ->
        {:error, "cannot exceed #{Limits.max_subscribed_events()} events"}

      true ->
        unknown = Enum.reject(events, &(&1 in Catalog.all_event_types()))
        if unknown == [], do: :ok, else: {:error, "unknown event type(s): #{Enum.join(unknown, ", ")}"}
    end
  end

  def subscribed_events_error(_events), do: {:error, "must be a list of event types"}
end
