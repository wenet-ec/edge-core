# edge_admin/lib/edge_admin/events/webhooks/limits.ex
defmodule EdgeAdmin.Events.Webhooks.Limits do
  @moduledoc """
  Shared numeric limits for webhook validation.

  When tightening a limit, update here. The change automatically takes
  effect at every layer that imports it.
  """

  @max_url_length 2048
  @min_secret_bytes 32
  @max_secret_bytes 256
  @max_headers 20
  @max_header_value_length 4096
  @min_subscribed_events 1
  @max_subscribed_events 20
  @max_event_type_length 256

  @doc "Maximum length of the destination URL in characters."
  def max_url_length, do: @max_url_length

  @doc "Minimum length of the HMAC signing secret in bytes."
  def min_secret_bytes, do: @min_secret_bytes

  @doc "Maximum length of the HMAC signing secret in bytes."
  def max_secret_bytes, do: @max_secret_bytes

  @doc "Maximum number of entries in the headers map."
  def max_headers, do: @max_headers

  @doc "Maximum length of a single header value in characters."
  def max_header_value_length, do: @max_header_value_length

  @doc "Minimum number of subscribed event types per webhook."
  def min_subscribed_events, do: @min_subscribed_events

  @doc "Maximum number of subscribed event types per webhook."
  def max_subscribed_events, do: @max_subscribed_events

  @doc "Maximum length of a single event-type string in characters."
  def max_event_type_length, do: @max_event_type_length
end
