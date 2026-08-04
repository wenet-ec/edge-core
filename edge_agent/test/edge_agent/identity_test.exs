# edge_agent/test/edge_agent/identity_test.exs
defmodule EdgeAgent.IdentityTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Identity

  describe "select_node_identity/2" do
    test "uses a persisted node ID and ignores a recovery key" do
      persisted_node_id = "018f0d7a-1234-7abc-8def-0123456789ab"
      recovery_key = recovery_key("b6f2f8a9-45c6-4c88-a2cd-3aeb39b9a8f2")

      assert {:ok, {:persisted, ^persisted_node_id, nil}} =
               Identity.select_node_identity(persisted_node_id, recovery_key)
    end

    test "uses the node ID encoded in a recovery key when no node ID is persisted" do
      node_id = "b6f2f8a9-45c6-4c88-a2cd-3aeb39b9a8f2"
      key = recovery_key(node_id)

      assert {:ok, {:recovery, ^node_id, ^key}} = Identity.select_node_identity(nil, key)
    end

    test "requests generated ID when neither source is present" do
      assert :generate = Identity.select_node_identity(nil, nil)
      assert :generate = Identity.select_node_identity("", "")
    end

    test "rejects malformed persisted IDs and recovery keys" do
      assert {:error, :invalid_persisted_node_id} = Identity.select_node_identity("not-a-uuid", nil)
      assert {:error, :invalid_recovery_key} = Identity.select_node_identity(nil, "not-base64")
      assert {:error, :invalid_recovery_key} = Identity.select_node_identity(nil, recovery_key("not-a-uuid"))

      missing_cluster_key =
        %{"node_id" => "b6f2f8a9-45c6-4c88-a2cd-3aeb39b9a8f2", "nonce" => "random-nonce"}
        |> JSON.encode!()
        |> Base.encode64()

      assert {:error, :invalid_recovery_key} = Identity.select_node_identity(nil, missing_cluster_key)
    end
  end

  defp recovery_key(node_id) do
    %{"node_id" => node_id, "cluster_name" => "production", "nonce" => "random-nonce"}
    |> JSON.encode!()
    |> Base.encode64()
  end
end
