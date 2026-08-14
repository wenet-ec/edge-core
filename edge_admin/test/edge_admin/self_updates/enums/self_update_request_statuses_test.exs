# edge_admin/test/edge_admin/self_updates/enums/self_update_request_statuses_test.exs
defmodule EdgeAdmin.SelfUpdates.Enums.SelfUpdateRequestStatusesTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Enums.SelfUpdateRequestStatuses

  test "statuses/0 returns all request statuses in canonical order" do
    assert SelfUpdateRequestStatuses.statuses() == [:pending, :processing, :completed]
  end

  test "status_strings/0 mirrors statuses/0 in wire format" do
    assert SelfUpdateRequestStatuses.status_strings() ==
             Enum.map(SelfUpdateRequestStatuses.statuses(), &Atom.to_string/1)
  end
end
