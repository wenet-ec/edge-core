# edge_admin/test/edge_admin/self_updates/views/self_update_request_view_test.exs
defmodule EdgeAdmin.SelfUpdates.Views.SelfUpdateRequestViewTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Views.SelfUpdateRequestView

  defp request_fixture(overrides \\ %{}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    base = %SelfUpdateRequest{
      id: "request-uuid-1",
      targeting: %{"type" => "all"},
      status: "pending",
      summary: nil,
      inserted_at: now,
      updated_at: now
    }

    struct(base, overrides)
  end

  describe "render/1" do
    test "produces every documented field with correct values" do
      request = request_fixture()

      result = SelfUpdateRequestView.render(request)

      assert result.id == request.id
      assert result.targeting == %{"type" => "all"}
      assert result.status == "pending"
      assert result.summary == nil
      assert result.inserted_at == request.inserted_at
      assert result.updated_at == request.updated_at
    end

    test "passes targeting maps through unchanged (string keys preserved)" do
      targeting = %{
        "type" => "clusters",
        "cluster_names" => ["prod"],
        "cluster_filters" => %{"has_node_limit" => true}
      }

      result = SelfUpdateRequestView.render(request_fixture(%{targeting: targeting}))

      assert result.targeting == targeting
    end

    test "passes summary maps through unchanged when populated" do
      summary = %{"total" => 10, "triggered" => 8, "failed" => 2}

      result = SelfUpdateRequestView.render(request_fixture(%{status: "completed", summary: summary}))

      assert result.status == "completed"
      assert result.summary == summary
    end

    test "preserves nil summary (no coercion to %{})" do
      result = SelfUpdateRequestView.render(request_fixture(%{summary: nil}))
      assert result.summary == nil
    end

    test "rendered map contains exactly the documented top-level keys" do
      result = SelfUpdateRequestView.render(request_fixture())

      expected_keys = Enum.sort(~w(id targeting status summary inserted_at updated_at)a)
      assert result |> Map.keys() |> Enum.sort() == expected_keys
    end
  end
end
