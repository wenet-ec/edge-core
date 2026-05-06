# edge_agent/lib/edge_agent_web/response_envelope.ex
defmodule EdgeAgentWeb.ResponseEnvelope do
  @moduledoc """
  Builds all HTTP response envelopes for the Edge Agent API.

  This is the single place that constructs top-level response maps.
  No other module should build `%{data: ..., meta: ...}` or `%{error: ..., meta: ...}` directly.

  ## Envelope shapes

  Single resource:
      %{data: %{...}, meta: %{request_id: "...", timestamp: "..."}}

  Error:
      %{error: %{code: "not_found", message: "...", details: nil}, meta: %{...}}

  ## Usage in views

      def show(%{conn: conn, command_execution: execution}) do
        ResponseEnvelope.success(conn, data(execution))
      end

  ## Usage in FallbackController / ErrorJSON

      ResponseEnvelope.error(conn, "not_found", "Resource not found")
      ResponseEnvelope.error(conn, "validation_failed", "Validation failed", field_errors)
  """

  @doc """
  Builds a success envelope around `data`. Accepts either a map (single
  resource — the common case) or a list (collection responses).
  """
  @spec success(Plug.Conn.t(), map() | list()) :: map()
  def success(conn, data) do
    %{
      data: data,
      meta: request_meta(conn)
    }
  end

  @doc """
  Builds an error envelope. `details` defaults to `nil` for simple errors and
  is omitted from the response in that case.
  Pass field-level error map for `validation_failed` (output of `Ecto.Changeset.traverse_errors/2`).
  """
  @spec error(Plug.Conn.t(), String.t(), String.t(), map() | nil) :: map()
  def error(conn, code, message, details \\ nil) do
    error_payload = %{code: code, message: message}

    error_payload =
      if is_nil(details), do: error_payload, else: Map.put(error_payload, :details, details)

    %{error: error_payload, meta: request_meta(conn)}
  end

  # --- Private ---

  defp request_meta(conn) do
    %{
      request_id: conn.assigns[:request_id],
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }
  end
end
