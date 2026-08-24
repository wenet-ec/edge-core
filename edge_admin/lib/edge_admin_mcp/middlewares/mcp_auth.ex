# edge_admin/lib/edge_admin_mcp/middlewares/mcp_auth.ex
defmodule EdgeAdminMcp.Middlewares.McpAuth do
  @moduledoc """
  MCP bearer authentication middleware.

  Validates the existing opaque `MCP_KEY` and `MASTER_KEY` bearer tokens and
  permits unauthenticated requests only for tools registered in the `:public`
  scope.
  """

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias EdgeAdminMcp.ToolRegistry

  @type status :: :authenticated | :anonymous | :invalid

  @spec call(map(), Frame.t()) :: :ok | {:error, term(), Frame.t()}
  def call(request, %Frame{} = frame) do
    case status(frame.context.headers) do
      :authenticated -> :ok
      :anonymous -> authorize_anonymous(request, frame)
      :invalid -> {:error, unauthorized_response(), frame}
    end
  end

  @doc false
  @spec authenticated?(Frame.t()) :: boolean()
  def authenticated?(%Frame{} = frame) do
    status(frame.context.headers) == :authenticated
  end

  @doc false
  @spec status(map()) :: status()
  def status(headers) when is_map(headers) do
    if Application.get_env(:edge_admin, :mcp_auth_enabled, true) do
      validate_headers(headers)
    else
      :authenticated
    end
  end

  def status(_headers), do: :invalid

  defp authorize_anonymous(%{"method" => "tools/call", "params" => %{"name" => name}}, frame) do
    if ToolRegistry.scope_for_tool(name) == :public do
      :ok
    else
      {:error, unauthorized_response(), frame}
    end
  end

  defp authorize_anonymous(_request, _frame), do: :ok

  defp validate_headers(headers) do
    case Map.get(headers, "authorization") do
      nil ->
        :anonymous

      "Bearer " <> token ->
        if valid_token?(token), do: :authenticated, else: :invalid

      _ ->
        :invalid
    end
  end

  defp valid_token?(token) do
    master_key = Application.get_env(:edge_admin, :master_key)
    mcp_key = Application.get_env(:edge_admin, :mcp_key)

    (is_binary(master_key) and Plug.Crypto.secure_compare(token, master_key)) or
      (is_binary(mcp_key) and Plug.Crypto.secure_compare(token, mcp_key))
  end

  defp unauthorized_response do
    Response.tool()
    |> Response.error("Authentication is required for this MCP tool")
    |> Response.to_protocol()
  end
end
