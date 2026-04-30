# edge_agent/lib/edge_agent_web/plugs/assign_request_id.ex
defmodule EdgeAgentWeb.Plugs.AssignRequestId do
  @moduledoc """
  Generates a UUIDv7 request ID and threads it through three places:

    * `x-request-id` response header — for clients to correlate requests
    * `conn.assigns.request_id` — for response envelopes to include in `meta`
    * `Logger.metadata(:request_id)` — so log lines emitted during the
      request carry the same id (matches what `Plug.RequestId` would do)

  This plug is the sole source of truth for request IDs. Inbound
  `x-request-id` headers are intentionally ignored — agent is a request
  origin, not a relay.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    request_id = Uniq.UUID.uuid7()
    Logger.metadata(request_id: request_id)

    conn
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
    |> Plug.Conn.assign(:request_id, request_id)
  end
end
