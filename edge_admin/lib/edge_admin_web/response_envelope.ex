# edge_admin/lib/edge_admin_web/response_builder.ex
defmodule EdgeAdminWeb.ResponseEnvelope do
  @moduledoc """
  Builds all HTTP response envelopes for the Edge Admin API.

  This is the single place that constructs top-level response maps.
  No other module should build `%{data: ..., meta: ...}` or `%{error: ..., meta: ...}` directly.

  ## Envelope shapes

  Single resource:
      %{data: %{...}, meta: %{request_id: "...", timestamp: "..."}}

  Paginated collection:
      %{data: [...], meta: %{request_id: "...", timestamp: "...", pagination: %{...}}}

  Error:
      %{error: %{code: "not_found", message: "...", details: nil}, meta: %{...}}

  ## Usage in views

      # show
      def show(%{conn: conn, node: node}) do
        ResponseEnvelope.success(conn, data(node))
      end

      # index (paginated)
      def index(%{conn: conn, nodes: nodes, meta: flop_meta}) do
        ResponseEnvelope.success(conn, Enum.map(nodes, &data/1), flop_meta)
      end

  ## Usage in FallbackController / ErrorJSON

      ResponseEnvelope.error(conn, "not_found", "Resource not found")
      ResponseEnvelope.error(conn, "validation_failed", "Validation failed", field_errors)
  """

  alias Flop.Meta

  @doc """
  Builds a success envelope for a single resource.
  """
  @spec success(Plug.Conn.t(), map() | list()) :: map()
  def success(conn, data) do
    %{
      data: data,
      meta: request_meta(conn)
    }
  end

  @doc """
  Builds a success envelope for a paginated collection.
  Accepts a `Flop.Meta` struct and maps only the fields relevant to page-based pagination.
  """
  @spec success(Plug.Conn.t(), list(), Meta.t()) :: map()
  def success(conn, data, %Meta{} = flop_meta) do
    %{
      data: data,
      meta:
        conn
        |> request_meta()
        |> Map.put(:pagination, pagination(flop_meta))
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

  defp pagination(%Meta{} = m) do
    %{
      page: m.current_page,
      page_size: m.page_size,
      total_count: m.total_count,
      total_pages: m.total_pages,
      has_next: m.has_next_page?,
      has_prev: m.has_previous_page?,
      next_page: m.next_page,
      prev_page: m.previous_page
    }
  end
end
