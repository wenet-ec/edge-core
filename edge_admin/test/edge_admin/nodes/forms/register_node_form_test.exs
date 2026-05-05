# edge_admin/test/edge_admin/nodes/forms/register_node_form_test.exs
defmodule EdgeAdmin.Nodes.Forms.RegisterNodeFormTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Nodes.Forms.RegisterNodeForm

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp cluster_found(_name), do: {:ok, %{name: "test"}}
  defp cluster_not_found(_name), do: {:error, :not_found}

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "node_id" => Ecto.UUID.generate(),
        "network_name" => "cluster-test",
        "id_type" => "persistent",
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

  # ---------------------------------------------------------------------------
  # changeset/2 — valid cases
  # ---------------------------------------------------------------------------

  describe "changeset/2 — valid cases" do
    test "all required fields present succeeds" do
      assert {:ok, result} = RegisterNodeForm.changeset(valid_attrs(), &cluster_found/1)
      assert result["id_type"] == "persistent"
      assert result["network_name"] == "cluster-test"
      assert result["http_port"] == 4000
    end

    test "random id_type succeeds" do
      assert {:ok, result} =
               RegisterNodeForm.changeset(valid_attrs(%{"id_type" => "random"}), &cluster_found/1)

      assert result["id_type"] == "random"
    end

    test "self_update_enabled true succeeds" do
      assert {:ok, result} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"self_update_enabled" => true}),
                 &cluster_found/1
               )

      assert result["self_update_enabled"] == true
    end

    test "port at boundary 1 is valid" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_port" => 1}), &cluster_found/1)
    end

    test "port at boundary 65535 is valid" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"http_port" => 65_535}),
                 &cluster_found/1
               )
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    for field <- [
          "node_id",
          "network_name",
          "id_type",
          "http_port",
          "ssh_port",
          "host_metrics_port",
          "wireguard_metrics_port",
          "http_proxy_port",
          "socks5_proxy_port",
          "version",
          "self_update_enabled"
        ] do
      test "missing #{field} is rejected" do
        attrs = Map.delete(valid_attrs(), unquote(field))

        assert {:error, changeset} = RegisterNodeForm.changeset(attrs, &cluster_found/1)
        field_atom = String.to_existing_atom(unquote(field))
        assert Map.has_key?(errors_on(changeset), field_atom)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — node_id UUID format
  # ---------------------------------------------------------------------------

  describe "changeset/2 — node_id UUID validation" do
    test "valid UUID is accepted" do
      uuid = Ecto.UUID.generate()
      assert {:ok, result} = RegisterNodeForm.changeset(valid_attrs(%{"node_id" => uuid}), &cluster_found/1)
      assert result["node_id"] == uuid
    end

    test "non-UUID string is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"node_id" => "not-a-uuid"}),
                 &cluster_found/1
               )

      assert %{node_id: [msg]} = errors_on(changeset)
      assert msg =~ "UUID"
    end

    test "empty node_id is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"node_id" => ""}), &cluster_found/1)

      assert %{node_id: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — network_name validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — network_name validation" do
    test "network_name starting with 'cluster-' is accepted" do
      assert {:ok, _} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"network_name" => "cluster-prod"}),
                 &cluster_found/1
               )
    end

    test "network_name without 'cluster-' prefix is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"network_name" => "prod"}),
                 &cluster_found/1
               )

      assert %{network_name: [msg]} = errors_on(changeset)
      assert msg =~ "cluster-"
    end

    test "network_name with wrong prefix is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"network_name" => "node-default"}),
                 &cluster_found/1
               )

      assert %{network_name: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — cluster existence (via injected callback)
  # ---------------------------------------------------------------------------

  describe "changeset/2 — cluster existence check" do
    test "cluster not found adds error on network_name field" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(), &cluster_not_found/1)

      assert %{network_name: [msg]} = errors_on(changeset)
      assert msg =~ "cluster does not exist"
    end

    test "callback receives cluster name without 'cluster-' prefix" do
      received = fn -> nil end |> Agent.start_link() |> elem(1)

      capturing_fn = fn name ->
        Agent.update(received, fn _ -> name end)
        {:ok, %{}}
      end

      RegisterNodeForm.changeset(valid_attrs(%{"network_name" => "cluster-mynet"}), capturing_fn)
      assert Agent.get(received, & &1) == "mynet"
      Agent.stop(received)
    end

    test "cluster check is skipped when network_name format is invalid" do
      called = :counters.new(1, [])

      counting_fn = fn _name ->
        :counters.add(called, 1, 1)
        {:ok, %{}}
      end

      {:error, _} =
        RegisterNodeForm.changeset(valid_attrs(%{"network_name" => "no-prefix"}), counting_fn)

      assert :counters.get(called, 1) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — id_type validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — id_type validation" do
    test "invalid id_type is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"id_type" => "hardware"}),
                 &cluster_found/1
               )

      assert %{id_type: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — port validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — port validation" do
    test "port 0 is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(valid_attrs(%{"http_port" => 0}), &cluster_found/1)

      assert %{http_port: [_msg]} = errors_on(changeset)
    end

    test "port 65536 exceeds maximum" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"ssh_port" => 65_536}),
                 &cluster_found/1
               )

      assert %{ssh_port: [_msg]} = errors_on(changeset)
    end

    test "negative port is rejected" do
      assert {:error, changeset} =
               RegisterNodeForm.changeset(
                 valid_attrs(%{"http_proxy_port" => -1}),
                 &cluster_found/1
               )

      assert %{http_proxy_port: [_msg]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # add_netmaker_not_found_error/0
  # ---------------------------------------------------------------------------

  describe "add_netmaker_not_found_error/0" do
    test "returns an error changeset with a node_id error" do
      assert {:error, %Ecto.Changeset{} = changeset} = RegisterNodeForm.add_netmaker_not_found_error()
      assert %{node_id: [msg]} = errors_on(changeset)
      assert msg =~ "not found in Netmaker"
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — to_map output
  # ---------------------------------------------------------------------------

  describe "changeset/2 — to_map output" do
    test "all registered fields are present in result" do
      {:ok, result} = RegisterNodeForm.changeset(valid_attrs(), &cluster_found/1)

      for key <- [
            "node_id",
            "network_name",
            "id_type",
            "http_port",
            "ssh_port",
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

  # ---------------------------------------------------------------------------
  # changeset/2 — invalid param types
  # ---------------------------------------------------------------------------

  describe "changeset/2 — invalid params" do
    test "non-map params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               RegisterNodeForm.changeset("bad", &cluster_found/1)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end

    test "nil params return a base error" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               RegisterNodeForm.changeset(nil, &cluster_found/1)

      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "expected a map"
    end
  end
end
