# edge_admin/test/edge_admin/nodes/forms/reregister_node_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.ReregisterNodeFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.ReregisterNodeForm

  defp errors_on(changeset), do: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "network_name" => "cluster-test",
        "http_port" => 4000,
        "ssh_port" => 40_022,
        "host_metrics_port" => 9100,
        "wireguard_metrics_port" => 9586,
        "http_proxy_port" => 8080,
        "socks5_proxy_port" => 1080,
        "version" => "1.0.0",
        "self_update_enabled" => false
      },
      overrides
    )
  end

  test "accepts authenticated node metadata without node ID or recovery key" do
    assert {:ok, result} = ReregisterNodeForm.changeset(valid_attrs())
    refute Map.has_key?(result, "node_id")
    refute Map.has_key?(result, "recovery_key")
  end

  test "rejects missing re-registration metadata" do
    assert {:error, changeset} =
             valid_attrs() |> Map.delete("version") |> ReregisterNodeForm.changeset()

    assert %{version: [_]} = errors_on(changeset)
  end
end
