# edge_admin/lib/edge_admin/admin_clustering/membership/membership.ex
defmodule EdgeAdmin.AdminClustering.Membership do
  @moduledoc """
  Public facade for Admin-cluster membership state.

  `Membership.Bootstrap` owns the startup join sequence. Cleanup and stale
  membership reaping live under the same lifecycle namespace, while this
  module remains the stable health-check API.
  """

  alias EdgeAdmin.AdminClustering.Membership.Bootstrap

  @doc "Returns true when the Admin-cluster bootstrap completed successfully."
  @spec initialized?() :: boolean()
  def initialized?, do: Bootstrap.initialized?()
end
