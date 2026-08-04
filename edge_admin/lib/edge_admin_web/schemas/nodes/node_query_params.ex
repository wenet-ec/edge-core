# edge_admin/lib/edge_admin_web/schemas/nodes/node_query_params.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeQueryParams do
  @moduledoc false

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.Schemas.QueryParams

  @status_enum Node.status_strings()

  @doc "Returns the shared REST filter contract for node collections."
  @spec filters() :: keyword()
  def filters do
    [
      QueryParams.uuid_in_filter(:node_id,
        description: "Filter by node IDs — comma-separated list of UUIDs (e.g. node_id__in=uuid1,uuid2)"
      ),
      QueryParams.enum_in_filter(:status, @status_enum,
        description: "Filter by node status (e.g. status__in=healthy,unhealthy)"
      ),
      QueryParams.string_filter(:version,
        description: "Filter by agent version (exact match or wildcard: 1.0.0, 1.*, etc.)"
      ),
      QueryParams.boolean_filter(:self_update_enabled, description: "Filter by self-update enabled status"),
      QueryParams.string_filter(:cluster_name,
        description: "Filter by cluster name — exact match or wildcard (prod*, *east, *rod*)"
      ),
      QueryParams.string_in_filter(:cluster_name,
        description: "Filter by cluster name — comma-separated list for IN match (e.g. cluster_name__in=prod,staging)"
      )
    ] ++
      QueryParams.datetime_range_filter(:last_seen_at) ++
      QueryParams.datetime_range_filter(:inserted_at) ++
      QueryParams.datetime_range_filter(:updated_at)
  end
end
