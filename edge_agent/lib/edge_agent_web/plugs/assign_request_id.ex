# edge_agent/lib/edge_agent_web/plugs/assign_request_id.ex
defmodule EdgeAgentWeb.Plugs.AssignRequestId do
  @moduledoc """
  Replaces the `x-request-id` set by `Plug.RequestId` with a UUID v7, then
  assigns it to `conn.assigns.request_id` so views can include it in response
  envelopes without needing direct access to response headers.

  Must be placed after `Plug.RequestId` in the endpoint pipeline.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    request_id = Uniq.UUID.uuid7()

    conn
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
    |> Plug.Conn.assign(:request_id, request_id)
  end
end
