# edge_admin/test/edge_admin/events/catalog_test.exs
defmodule EdgeAdmin.Events.CatalogTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp cluster_fixture, do: %Cluster{id: "cluster-uuid-1", name: "prod"}

  defp node_fixture(overrides \\ %{}) do
    cluster = cluster_fixture()

    base = %Node{
      id: "node-uuid-1",
      cluster: cluster,
      cluster_id: cluster.id,
      status: :healthy,
      version: "1.2.0",
      id_type: "persistent",
      http_port: 44_000,
      ssh_port: 40_022,
      host_metrics_port: 9100,
      wireguard_metrics_port: 9101,
      http_proxy_port: 44_001,
      socks5_proxy_port: 44_002,
      self_update_enabled: true,
      api_token: "token-secret",
      proxy_password: "proxy-secret",
      netmaker_host_id: "host-1",
      last_seen_at: now(),
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  defp enrollment_key_fixture(overrides) do
    cluster = cluster_fixture()

    base = %EnrollmentKey{
      id: "key-uuid-1",
      name: "default-key",
      key: "secret-key-blob-do-not-leak",
      uses_remaining: 4,
      cluster_id: cluster.id,
      cluster: cluster,
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  defp execution_fixture(overrides \\ %{}) do
    base = %CommandExecution{
      id: "exec-uuid-1",
      command_id: "cmd-uuid-1",
      node_id: "node-uuid-1",
      target_all: false,
      status: :pending,
      output: "should not be in event payload",
      exit_code: nil,
      sent_at: nil,
      completed_at: nil,
      cancelled_at: nil,
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  defp command_fixture(overrides \\ %{}) do
    base = %Command{
      id: "cmd-uuid-1",
      command_text: "uname -a",
      timeout: 30_000,
      expired_at: nil,
      targeting: %{"type" => "all"},
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  defp ssh_username_fixture(overrides \\ %{}) do
    base = %SshUsername{
      id: "sshuser-uuid-1",
      username: "deploy",
      password_hash: "$argon2id$do-not-leak",
      node_id: "node-uuid-1",
      node: %Node{id: "node-uuid-1", cluster: cluster_fixture()},
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  defp self_update_request_fixture(overrides \\ %{}) do
    base = %SelfUpdateRequest{
      id: "selfupd-uuid-1",
      targeting: %{"type" => "all"},
      status: :completed,
      summary: %{"total" => 10, "triggered" => 9, "failed" => 1},
      inserted_at: now(),
      updated_at: now()
    }

    struct(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # all_event_types/0 — pinned set; webhook validation + AsyncAPI both depend
  # on this list staying authoritative.
  # ---------------------------------------------------------------------------

  describe "all_event_types/0" do
    test "returns the 15 documented event types in catalog order" do
      assert Catalog.all_event_types() == [
               "edge.enrollment_key.verified",
               "edge.node.registered",
               "edge.node.reregistered",
               "edge.node.version_changed",
               "edge.node.status_changed",
               "edge.node.cluster_changed",
               "edge.node.update_triggered",
               "edge.command_execution.created",
               "edge.command_execution.sent",
               "edge.command_execution.completed",
               "edge.command_execution.cancelled",
               "edge.command_execution.expired",
               "edge.command_execution.pruned",
               "edge.ssh_username.verified",
               "edge.self_update_request.completed"
             ]
    end

    test "no duplicates" do
      types = Catalog.all_event_types()
      assert length(types) == length(Enum.uniq(types))
    end

    test "every type follows the 'edge.<domain>.<verb>' shape" do
      for type <- Catalog.all_event_types() do
        assert String.starts_with?(type, "edge."),
               "expected #{inspect(type)} to start with 'edge.'"

        assert length(String.split(type, ".")) == 3,
               "expected #{inspect(type)} to have exactly three dot-separated parts"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # event_type/1 — round-trip with all_event_types/0
  # ---------------------------------------------------------------------------

  describe "event_type/1" do
    test "every struct produces a registered event type" do
      structs = [
        %Catalog.EnrollmentKeyVerified{result: :verified},
        %Catalog.NodeRegistered{node: node_fixture()},
        %Catalog.NodeReregistered{node: node_fixture()},
        %Catalog.NodeVersionChanged{node: node_fixture(), previous_version: "1.1.0"},
        %Catalog.NodeStatusChanged{node: node_fixture(), previous_status: :healthy},
        %Catalog.NodeClusterChanged{node: node_fixture(), previous_cluster_name: "old"},
        %Catalog.NodeUpdateTriggered{node: node_fixture(), self_update_request_id: "req"},
        %Catalog.CommandExecutionCreated{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionSent{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionCompleted{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionCancelled{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionExpired{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionPruned{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.SshUsernameVerified{
          ssh_username: ssh_username_fixture(),
          node_id: "node-1",
          attempted_username: "deploy",
          auth_method: :password,
          result: :success
        },
        %Catalog.SelfUpdateCompleted{request: self_update_request_fixture()}
      ]

      registered = Catalog.all_event_types()

      for s <- structs do
        type = Catalog.event_type(s)

        assert type in registered,
               "expected #{inspect(s.__struct__)} -> #{inspect(type)} to be in all_event_types/0"
      end

      # Also: every registered type must be produced by some struct in our list.
      produced = Enum.map(structs, &Catalog.event_type/1)
      assert Enum.sort(produced) == Enum.sort(registered)
    end

    test "specific mappings are pinned" do
      assert Catalog.event_type(%Catalog.NodeRegistered{node: node_fixture()}) ==
               "edge.node.registered"

      assert Catalog.event_type(%Catalog.EnrollmentKeyVerified{result: :verified}) ==
               "edge.enrollment_key.verified"

      assert Catalog.event_type(%Catalog.SelfUpdateCompleted{
               request: self_update_request_fixture()
             }) == "edge.self_update_request.completed"
    end
  end

  # ---------------------------------------------------------------------------
  # to_data/1 — payload builders. Security contracts:
  #   • enrollment_key.key blob NEVER appears
  #   • ssh_username.password_hash NEVER appears
  #   • node.api_token / node.proxy_password NEVER appear
  #   • execution.output NEVER appears (operators may have logged secrets there)
  # ---------------------------------------------------------------------------

  describe "to_data/1 — EnrollmentKeyVerified (security)" do
    test "verified case excludes the key blob" do
      key = enrollment_key_fixture(%{key: "secret-blob"})
      data = Catalog.to_data(%Catalog.EnrollmentKeyVerified{enrollment_key: key, result: :verified})

      refute Map.has_key?(data, "key")
      refute data |> inspect() |> String.contains?("secret-blob")

      assert data["enrollment_key_id"] == key.id
      assert data["cluster_name"] == "prod"
      assert data["name"] == key.name
      assert data["uses_remaining"] == key.uses_remaining
      assert data["result"] == "verified"
      assert is_binary(data["verified_at"])
    end

    test "invalid_key case (no DB row) yields nil identifying fields, not a crash" do
      data = Catalog.to_data(%Catalog.EnrollmentKeyVerified{result: :invalid_key})

      assert data["enrollment_key_id"] == nil
      assert data["cluster_name"] == nil
      assert data["name"] == nil
      assert data["uses_remaining"] == nil
      assert data["result"] == "invalid_key"
      assert is_binary(data["verified_at"])
    end

    test "all result variants serialize correctly" do
      for result <- [:verified, :invalid_key, :key_expired, :key_spent, :node_limit_reached] do
        data = Catalog.to_data(%Catalog.EnrollmentKeyVerified{result: result})
        assert data["result"] == Atom.to_string(result)
      end
    end
  end

  describe "to_data/1 — Node events (security)" do
    test "node payload excludes api_token, proxy_password, and netmaker_host_id" do
      node = node_fixture(%{api_token: "leaked-token", proxy_password: "leaked-proxy-pw"})
      data = Catalog.to_data(%Catalog.NodeRegistered{node: node})

      refute Map.has_key?(data, "api_token")
      refute Map.has_key?(data, "proxy_password")
      refute Map.has_key?(data, "netmaker_host_id")

      # Defensive: the inspected payload contains neither secret.
      inspected = inspect(data)
      refute inspected =~ "leaked-token"
      refute inspected =~ "leaked-proxy-pw"
    end

    test "NodeRegistered carries the documented base fields" do
      node = node_fixture()
      data = Catalog.to_data(%Catalog.NodeRegistered{node: node})

      assert data["node_id"] == node.id
      assert data["cluster_name"] == "prod"
      assert data["status"] == "healthy"
      assert data["version"] == "1.2.0"
      assert data["id_type"] == "persistent"
      assert data["http_port"] == 44_000
      assert data["ssh_port"] == 40_022
      assert data["host_metrics_port"] == 9100
      assert data["wireguard_metrics_port"] == 9101
      assert data["http_proxy_port"] == 44_001
      assert data["socks5_proxy_port"] == 44_002
      assert data["self_update_enabled"] == true
      assert is_binary(data["last_seen_at"])
      assert is_binary(data["inserted_at"])
      assert is_binary(data["updated_at"])
    end

    test "NodeRegistered handles missing cluster preload (cluster_name nil)" do
      node = node_fixture(%{cluster: %Ecto.Association.NotLoaded{}})
      data = Catalog.to_data(%Catalog.NodeRegistered{node: node})

      assert data["cluster_name"] == nil
      assert data["node_id"] == node.id
    end

    test "NodeReregistered uses the same base shape" do
      data = Catalog.to_data(%Catalog.NodeReregistered{node: node_fixture()})
      assert data["node_id"] == "node-uuid-1"
      assert data["cluster_name"] == "prod"
    end

    test "NodeVersionChanged overlays previous_version onto base" do
      data =
        Catalog.to_data(%Catalog.NodeVersionChanged{
          node: node_fixture(%{version: "2.0.0"}),
          previous_version: "1.1.0"
        })

      assert data["version"] == "2.0.0"
      assert data["previous_version"] == "1.1.0"
    end

    test "NodeStatusChanged overlays previous_status onto base" do
      data =
        Catalog.to_data(%Catalog.NodeStatusChanged{
          node: node_fixture(%{status: :unhealthy}),
          previous_status: :healthy
        })

      assert data["status"] == "unhealthy"
      assert data["previous_status"] == "healthy"
    end

    test "NodeClusterChanged overlays previous_cluster_name" do
      data =
        Catalog.to_data(%Catalog.NodeClusterChanged{
          node: node_fixture(),
          previous_cluster_name: "staging"
        })

      assert data["cluster_name"] == "prod"
      assert data["previous_cluster_name"] == "staging"
    end

    test "NodeUpdateTriggered overlays self_update_request_id" do
      data =
        Catalog.to_data(%Catalog.NodeUpdateTriggered{
          node: node_fixture(),
          self_update_request_id: "req-123"
        })

      assert data["self_update_request_id"] == "req-123"
    end
  end

  describe "to_data/1 — CommandExecution events (security: output excluded)" do
    test "execution payload excludes `output` (may contain secrets the user logged)" do
      execution = execution_fixture(%{output: "DATABASE_URL=postgres://leaked"})
      command = command_fixture()

      data =
        Catalog.to_data(%Catalog.CommandExecutionCompleted{
          execution: execution,
          command: command,
          cluster_name: "prod"
        })

      refute Map.has_key?(data, "output")
      refute data |> inspect() |> String.contains?("leaked")
    end

    test "execution payload carries identity, command metadata, and timestamps" do
      execution =
        execution_fixture(%{
          status: :completed,
          exit_code: 0,
          sent_at: now(),
          completed_at: now()
        })

      command = command_fixture(%{command_text: "ls", timeout: 5_000})

      data =
        Catalog.to_data(%Catalog.CommandExecutionCompleted{
          execution: execution,
          command: command,
          cluster_name: "prod"
        })

      assert data["command_execution_id"] == execution.id
      assert data["command_id"] == execution.command_id
      assert data["node_id"] == execution.node_id
      assert data["cluster_name"] == "prod"
      assert data["command_text"] == "ls"
      assert data["timeout"] == 5_000
      assert data["status"] == "completed"
      assert data["exit_code"] == 0
      assert data["target_all"] == false
      assert is_binary(data["sent_at"])
      assert is_binary(data["completed_at"])
      assert data["cancelled_at"] == nil
    end

    test "all six command_execution events use the same execution_data shape" do
      structs = [
        %Catalog.CommandExecutionCreated{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionSent{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionCompleted{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionCancelled{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionExpired{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        },
        %Catalog.CommandExecutionPruned{
          execution: execution_fixture(),
          command: command_fixture(),
          cluster_name: "prod"
        }
      ]

      keys =
        ~w(command_execution_id command_id node_id cluster_name command_text timeout
           status exit_code target_all expired_at sent_at completed_at cancelled_at
           inserted_at updated_at)

      for s <- structs do
        data = Catalog.to_data(s)
        assert data |> Map.keys() |> Enum.sort() == Enum.sort(keys)
      end
    end
  end

  describe "to_data/1 — SshUsernameVerified (security)" do
    test "payload excludes password_hash and any public_key strings" do
      user = ssh_username_fixture(%{password_hash: "$argon2id$leaked-hash"})

      data =
        Catalog.to_data(%Catalog.SshUsernameVerified{
          ssh_username: user,
          node_id: user.node_id,
          attempted_username: "deploy",
          auth_method: :password,
          result: :success
        })

      refute Map.has_key?(data, "password_hash")
      refute data |> inspect() |> String.contains?("leaked-hash")

      # public_key is not echoed even when discussed (the auth_method case).
      refute Map.has_key?(data, "public_key")
    end

    test "verified-existing-user case carries identity and decision" do
      user = ssh_username_fixture()

      data =
        Catalog.to_data(%Catalog.SshUsernameVerified{
          ssh_username: user,
          node_id: user.node_id,
          attempted_username: "deploy",
          auth_method: :public_key,
          result: :success
        })

      assert data["ssh_username_id"] == user.id
      assert data["node_id"] == user.node_id
      assert data["cluster_name"] == "prod"
      assert data["username"] == "deploy"
      assert data["auth_method"] == "public_key"
      assert data["result"] == "success"
      assert is_binary(data["verified_at"])
    end

    test "missing-user case (failed attempt against unknown username) still emits an event" do
      data =
        Catalog.to_data(%Catalog.SshUsernameVerified{
          ssh_username: nil,
          node_id: "node-1",
          attempted_username: "nobody",
          auth_method: :unknown,
          result: :failure
        })

      assert data["ssh_username_id"] == nil
      assert data["node_id"] == "node-1"
      assert data["cluster_name"] == nil
      assert data["username"] == "nobody"
      assert data["auth_method"] == "unknown"
      assert data["result"] == "failure"
    end

    test "auth_method and result enums all serialize as strings" do
      for auth_method <- [:password, :public_key, :unknown],
          result <- [:success, :failure] do
        data =
          Catalog.to_data(%Catalog.SshUsernameVerified{
            ssh_username: nil,
            node_id: "n",
            attempted_username: "u",
            auth_method: auth_method,
            result: result
          })

        assert data["auth_method"] == Atom.to_string(auth_method)
        assert data["result"] == Atom.to_string(result)
      end
    end
  end

  describe "to_data/1 — SelfUpdateCompleted" do
    test "carries id, status, targeting, summary, and timestamps" do
      request = self_update_request_fixture()
      data = Catalog.to_data(%Catalog.SelfUpdateCompleted{request: request})

      assert data["self_update_request_id"] == request.id
      assert data["status"] == "completed"
      assert data["targeting"] == %{"type" => "all"}
      assert data["summary"] == %{"total" => 10, "triggered" => 9, "failed" => 1}
      assert is_binary(data["inserted_at"])
      assert is_binary(data["updated_at"])
    end

    test "passes nil summary through unchanged" do
      data =
        Catalog.to_data(%Catalog.SelfUpdateCompleted{
          request: self_update_request_fixture(%{summary: nil})
        })

      assert data["summary"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # description/1, data_example/1, lookup/1, list_with_descriptions/0
  # ---------------------------------------------------------------------------

  describe "description/1" do
    test "returns a non-empty string for every catalog event type" do
      for type <- Catalog.all_event_types() do
        desc = Catalog.description(type)
        assert is_binary(desc), "expected #{inspect(type)} to have a description"
        assert desc != "", "expected #{inspect(type)} description to be non-empty"
      end
    end

    test "returns nil for unknown event type" do
      assert Catalog.description("edge.does_not_exist") == nil
    end
  end

  describe "data_example/1" do
    test "returns a map for every catalog event type" do
      for type <- Catalog.all_event_types() do
        example = Catalog.data_example(type)
        assert is_map(example), "expected #{inspect(type)} to have a data example"
        assert map_size(example) > 0
      end
    end

    test "returns nil for unknown event type" do
      assert Catalog.data_example("edge.does_not_exist") == nil
    end
  end

  describe "lookup/1" do
    test "returns aggregated metadata for a known event type" do
      assert {:ok, info} = Catalog.lookup("edge.node.registered")
      assert info.type == "edge.node.registered"
      assert is_binary(info.description)
      assert is_map(info.data_example)
      assert info.reference == "/asyncdoc"
    end

    test "returns :not_found for unknown event type" do
      assert Catalog.lookup("edge.does_not_exist") == {:error, :not_found}
    end
  end

  describe "list_with_descriptions/0" do
    test "returns one entry per catalog type, in catalog order" do
      result = Catalog.list_with_descriptions()

      assert length(result) == length(Catalog.all_event_types())
      assert Enum.map(result, & &1.type) == Catalog.all_event_types()

      for entry <- result do
        assert entry |> Map.keys() |> Enum.sort() == [:description, :type]
        assert is_binary(entry.description)
      end
    end
  end
end
