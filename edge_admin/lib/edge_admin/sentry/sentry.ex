# edge_admin/lib/edge_admin/sentry/sentry.ex
defmodule EdgeAdmin.Sentry do
  @moduledoc false
  @scrubbed_keys [
    "first_name",
    "last_name",
    "email",
    "password",
    "authorization",
    "proxy_authorization",
    "x_api_key",
    "api_token",
    "api_key",
    "proxy_password",
    "recovery_key",
    "enrollment_token",
    "enrollment_key",
    "vpn_enrollment_key",
    "ingress_private_key",
    "private_key",
    "master_key",
    "encryption_key",
    "secret_key_base",
    "password_hash",
    "credential",
    "credentials",
    "secret",
    "token",
    "headers"
  ]
  @scrubbed_value "*********"

  def scrub_params(conn) do
    conn
    |> Sentry.PlugContext.default_body_scrubber()
    |> scrub_map(@scrubbed_keys)
  end

  def scrubbed_remote_address(_conn), do: @scrubbed_value

  @dropped_exceptions [
    "Elixir.Phoenix.Router.NoRouteError",
    "Elixir.Plug.Parsers.UnsupportedMediaTypeError",
    "Elixir.Plug.Parsers.RequestTooLargeError",
    "Elixir.DBConnection.OwnershipError"
  ]

  def before_send(%Sentry.Event{original_exception: %{__struct__: mod}} = event) do
    if Atom.to_string(mod) in @dropped_exceptions, do: false, else: scrub_struct(event)
  end

  def before_send(%Sentry.Event{} = event), do: scrub_struct(event)
  def before_send(event), do: event

  defp scrub_map(map, scrubbed_keys) do
    Map.new(map, fn {key, value} ->
      value = if scrubbed_key?(key, scrubbed_keys), do: @scrubbed_value, else: scrub_value(value, scrubbed_keys)
      {key, value}
    end)
  end

  defp scrub_struct(struct) do
    fields = struct |> Map.from_struct() |> scrub_map(@scrubbed_keys)
    struct(struct.__struct__, fields)
  end

  defp scrub_value(value, keys) when is_struct(value) do
    fields = value |> Map.from_struct() |> scrub_map(keys)
    struct(value.__struct__, fields)
  end

  defp scrub_value(value, keys) when is_map(value) do
    Map.new(value, fn {key, item} ->
      value = if scrubbed_key?(key, keys), do: @scrubbed_value, else: scrub_value(item, keys)
      {key, value}
    end)
  end

  defp scrub_value(value, keys) when is_list(value), do: Enum.map(value, &scrub_value(&1, keys))

  defp scrub_value(value, keys) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&scrub_value(&1, keys))
    |> List.to_tuple()
  end

  defp scrub_value(value, _keys) when is_binary(value), do: scrub_text(value)
  defp scrub_value(value, _keys), do: value

  defp scrubbed_key?(key, scrubbed_keys) do
    case key do
      key when is_atom(key) -> normalize_key(Atom.to_string(key)) in scrubbed_keys
      key when is_binary(key) -> normalize_key(key) in scrubbed_keys
      _ -> false
    end
  end

  defp normalize_key(key) do
    key
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.replace(~r/[-\s]/, "_")
  end

  defp scrub_text(text) do
    text
    |> String.replace(
      ~r/\b(authorization|proxy-authorization)\s*[:=]\s*(?:bearer\s+)?[^\s,;"<>]+/i,
      "\\1: #{@scrubbed_value}"
    )
    |> String.replace(
      ~r/\b(master[_ -]?key|encryption[_ -]?key|secret[_ -]?key[_ -]?base|api[_ -]?token|ingress[_ -]?private[_ -]?key|password|proxy[_ -]?password|recovery[_ -]?key|enrollment[_ -]?(token|key))\s*[:=]\s*[^\s,;"<>]+/i,
      "\\1: #{@scrubbed_value}"
    )
  end
end
