# edge_admin/lib/edge_admin/sentry/sentry.ex
defmodule EdgeAdmin.Sentry do
  @moduledoc false
  @scrubbed_keys [
    "first_name",
    "last_name",
    "email",
    "password",
    "api_token",
    "proxy_password",
    "enrollment_token",
    "enrollment_key",
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
    if Atom.to_string(mod) in @dropped_exceptions, do: false, else: event
  end

  def before_send(event), do: event

  # Reference: https://github.com/getsentry/sentry-elixir/blob/9.1.0/lib/sentry/plug_context.ex#L232
  defp scrub_map(map, scrubbed_keys) do
    Map.new(map, fn {key, value} ->
      value =
        cond do
          key in scrubbed_keys -> @scrubbed_value
          is_struct(value) -> value |> Map.from_struct() |> scrub_map(scrubbed_keys)
          is_map(value) -> scrub_map(value, scrubbed_keys)
          is_list(value) -> scrub_list(value, scrubbed_keys)
          true -> value
        end

      {key, value}
    end)
  end

  # Reference: https://github.com/getsentry/sentry-elixir/blob/9.1.0/lib/sentry/plug_context.ex#L248
  defp scrub_list(list, scrubbed_keys) do
    Enum.map(list, fn value ->
      cond do
        is_struct(value) -> value |> Map.from_struct() |> scrub_map(scrubbed_keys)
        is_map(value) -> scrub_map(value, scrubbed_keys)
        is_list(value) -> scrub_list(value, scrubbed_keys)
        true -> value
      end
    end)
  end
end
