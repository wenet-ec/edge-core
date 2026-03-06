# edge_agent/test/edge_agent/vpn_test.exs
#
# EdgeAgent.Vpn now handles only the VPN join/health-check lifecycle.
# All enrollment key extraction and fetching moved to EdgeAgent.Enrollment.
#
# join_if_needed/1 and all helpers call Nexmaker.Cli (netclient binary) or
# Process.sleep — integration only, no unit tests here.
#
# This file is intentionally empty. Unit tests for the enrollment flow live in:
#   test/edge_agent/enrollment_test.exs
#
defmodule EdgeAgent.VpnTest do
  use ExUnit.Case, async: true
  # No testable pure logic remains in EdgeAgent.Vpn after the enrollment refactor.
end
