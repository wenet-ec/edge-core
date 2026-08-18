# edge_admin/test/edge_admin/nodes/forms/register_node_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.RegisterNodeFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.RegisterNodeForm
  # helpers

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "node_id" => Uniq.UUID.uuid7(),
        "network_name" => "cluster-test",
        "http_port" => 4000,
        "ssh_port" => 40_022,
        "agent_metrics_port" => 44_000,
        "host_metrics_port" => 9100,
        "wireguard_metrics_port" => 9586,
        "http_proxy_port" => 8080,
        "socks5_proxy_port" => 1080,
        "version" => "1.0.0",
        "self_update_enabled" => false,
        "enrollment_key_id" => Uniq.UUID.uuid7()
      },
      overrides
    )
  end

  # changeset/1 — valid cases

  describe "changeset/1 — valid cases" do
    test "all required fields present succeeds" do
      assert {:ok, result} = RegisterNodeForm.changeset(valid_attrs())
      assert result["network_name"] == "cluster-test"
      assert result["http_port"] == 4000
    end

    test "self_update_enabled true succeeds" do
      assert {:ok, result} =
               RegisterNodeForm.changeset(valid_attrs(%{"self_update_enabled" => true}))

      assert result["self_update_enabled"] == true
    end

    test "preserves an optional recovery key" do
      assert {:ok, result} =
               RegisterNodeForm.changeset(valid_attrs(%{"recovery_key" => "recovery-key"}))

      assert result["recovery_key"] == "recovery-key"
    end

    test "preserves the required enrollment key ID" do
      enrollment_key_id = Uniq.UUID.uuid7()

      assert {:ok, result} =
               RegisterNodeForm.changeset(valid_attrs(%{"enrollment_key_id" => enrollment_key_id}))

      assert result["enrollment_key_id"] == enrollment_key_id
    end

    test "port at boundary 1 is valid" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_port" => 1}))
    end

    test "port at boundary 65535 is valid" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_port" => 65_535}))
    end
  end

  # changeset/1 — required fields

  describe "changeset/1 — required fields" do
    for field <- [
          "node_id",
          "network_name",
          "http_port",
          "ssh_port",
          "agent_metrics_port",
          "host_metrics_port",
          "wireguard_metrics_port",
          "http_proxy_port",
          "socks5_proxy_port",
          "version",
          "self_update_enabled",
          "enrollment_key_id"
        ] do
      test "missing #{field} is rejected" do
        attrs = Map.delete(valid_attrs(), unquote(field))

        assert {:error, changeset} = RegisterNodeForm.changeset(attrs)
        field_atom = String.to_existing_atom(unquote(field))
        assert Map.has_key?(errors_on(changeset), field_atom)
      end
    end
  end

  # changeset/1 — node_id UUID format

  describe "changeset/1 — node_id UUID validation" do
    test "valid UUID is accepted" do
      uuid = Uniq.UUID.uuid7()
      assert {:ok, result} = RegisterNodeForm.changeset(valid_attrs(%{"node_id" => uuid}))
      assert result["node_id"] == uuid
    end

    test "valid UUIDv4 is accepted at the public form boundary" do
      uuid = Ecto.UUID.generate()

      assert {:ok, result} = RegisterNodeForm.changeset(valid_attrs(%{"node_id" => uuid}))
      assert result["node_id"] == uuid
    end

    test "non-UUID string is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"node_id" => "not-a-uuid"}))

      assert %{node_id: [msg]} = errors_on(changeset)
      assert msg =~ "UUID"
    end

    test "empty node_id is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"node_id" => ""}))

      assert %{node_id: [_msg]} = errors_on(changeset)
    end
  end

  # changeset/1 — network_name validation

  describe "changeset/1 — network_name validation" do
    test "network_name starting with 'cluster-' is accepted" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(valid_attrs(%{"network_name" => "cluster-prod"}))
    end

    test "network_name without 'cluster-' prefix is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"network_name" => "prod"}))

      assert %{network_name: [msg]} = errors_on(changeset)
      assert msg =~ "cluster-"
    end

    test "network_name with wrong prefix is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"network_name" => "node-default"}))

      assert %{network_name: [_msg]} = errors_on(changeset)
    end
  end

  # changeset/1 — port validation

  describe "changeset/1 — port validation" do
    test "port 0 is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_port" => 0}))

      assert %{http_port: [_msg]} = errors_on(changeset)
    end

    test "port 65536 exceeds maximum" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"ssh_port" => 65_536}))

      assert %{ssh_port: [_msg]} = errors_on(changeset)
    end

    test "negative port is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_proxy_port" => -1}))

      assert %{http_proxy_port: [_msg]} = errors_on(changeset)
    end
  end

  # changeset/1 — to_map output

  describe "changeset/1 — to_map output" do
    test "all registered fields are present in result" do
      {:ok, result} = RegisterNodeForm.changeset(valid_attrs())

      for key <- [
            "node_id",
            "network_name",
            "http_port",
            "ssh_port",
            "agent_metrics_port",
            "host_metrics_port",
            "wireguard_metrics_port",
            "http_proxy_port",
            "socks5_proxy_port",
            "version",
            "self_update_enabled"
          ] do
        assert Map.has_key?(result, key), "expected key #{key} in result"
      end
    end
  end
end
