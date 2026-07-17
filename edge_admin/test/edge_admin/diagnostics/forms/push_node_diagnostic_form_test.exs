# edge_admin/test/edge_admin/diagnostics/forms/push_node_diagnostic_form_test.exs
defmodule EdgeAdmin.Diagnostics.Forms.PushNodeDiagnosticFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Diagnostics.Forms.PushNodeDiagnosticForm

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "diagnostic" => %{
          "collected_at" => "2026-07-17T00:00:00Z",
          "overall" => "pass",
          "checks" => []
        }
      },
      overrides
    )
  end

  test "accepts a diagnostic report" do
    assert {:ok, %{"diagnostic" => diagnostic}} =
             PushNodeDiagnosticForm.changeset(valid_attrs())

    assert diagnostic["overall"] == "pass"
  end

  test "requires the diagnostic wrapper" do
    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(%{})
    assert %{diagnostic: [_message]} = errors_on(changeset)
  end

  test "requires collected_at, overall, and checks" do
    attrs = valid_attrs(%{"diagnostic" => %{"overall" => "pass"}})

    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(attrs)
    assert %{diagnostic: messages} = errors_on(changeset)
    assert "must include collected_at" in messages
    assert "must include checks" in messages
  end

  test "validates overall values" do
    attrs =
      valid_attrs(%{
        "diagnostic" => %{"collected_at" => "2026-07-17T00:00:00Z", "overall" => "unknown", "checks" => []}
      })

    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(attrs)
    assert %{diagnostic: messages} = errors_on(changeset)
    assert "overall must be pass, warn, or fail" in messages
  end

  test "requires collected_at to be an ISO 8601 date-time" do
    attrs =
      valid_attrs(%{
        "diagnostic" => %{"collected_at" => "not-a-date", "overall" => "pass", "checks" => []}
      })

    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(attrs)
    assert %{diagnostic: messages} = errors_on(changeset)
    assert "collected_at must be an ISO 8601 date-time" in messages
  end

  test "requires checks to contain objects" do
    attrs =
      valid_attrs(%{
        "diagnostic" => %{"collected_at" => "2026-07-17T00:00:00Z", "overall" => "pass", "checks" => ["bad"]}
      })

    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(attrs)
    assert %{diagnostic: messages} = errors_on(changeset)
    assert "checks must contain valid diagnostic checks" in messages
  end

  test "rejects an unknown diagnostic check" do
    attrs =
      valid_attrs(%{
        "diagnostic" => %{
          "collected_at" => "2026-07-17T00:00:00Z",
          "overall" => "pass",
          "checks" => [%{"name" => "unknown", "status" => "pass", "duration_ms" => 1, "details" => %{}}]
        }
      })

    assert {:error, changeset} = PushNodeDiagnosticForm.changeset(attrs)
    assert %{diagnostic: messages} = errors_on(changeset)
    assert "checks must contain valid diagnostic checks" in messages
  end

  test "rejects non-map parameters" do
    assert {:error, changeset} = PushNodeDiagnosticForm.changeset("not a map")
    assert %{base: ["invalid parameters - expected a map"]} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
