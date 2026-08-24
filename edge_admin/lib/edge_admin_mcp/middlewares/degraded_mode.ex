# edge_admin/lib/edge_admin_mcp/middlewares/degraded_mode.ex
defmodule EdgeAdminMcp.Middlewares.DegradedMode do
  @moduledoc """
  Blocks MCP writes that are unavailable while the Admin cluster is degraded.
  """

  alias Anubis.Server.Frame
  alias Anubis.Server.Response
  alias EdgeAdminMcp.ToolError
  alias EdgeAdminMcp.ToolRegistry

  @metadata_module Application.compile_env(:edge_admin, :metadata_module, EdgeAdmin.AdminClustering.Metadata)
  @compile {:no_warn_undefined, @metadata_module}

  @spec call(map(), Frame.t()) :: :ok | {:error, term(), Frame.t()}
  def call(request, %Frame{} = frame) do
    case check(request) do
      :ok -> :ok
      :degraded -> {:error, degraded_response(), frame}
    end
  end

  defp check(%{"method" => "tools/call", "params" => %{"name" => name}}) do
    check_tool(name)
  end

  defp check(_request), do: :ok

  defp check_tool(name) do
    if ToolRegistry.degraded_behavior(name) == :block and @metadata_module.degraded?() do
      :degraded
    else
      :ok
    end
  end

  defp degraded_response do
    Response.tool() |> Response.error(ToolError.message(:degraded_mode)) |> Response.to_protocol()
  end
end
