# edge_admin/lib/edge_admin_health/edge_admin_health.ex
defmodule EdgeAdminHealth do
  @moduledoc false
  @health_check_error_code 422

  def checks do
    [
      %PlugCheckup.Check{name: "NOOP", module: __MODULE__, function: :noop_health}
    ]
  end

  def error_code, do: @health_check_error_code

  def noop_health, do: :ok
end
