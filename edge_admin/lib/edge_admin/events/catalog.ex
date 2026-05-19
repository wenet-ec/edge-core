# edge_admin/lib/edge_admin/events/catalog.ex
defmodule EdgeAdmin.Events.Catalog do
  @moduledoc """
  Single source of truth for the event catalog.

  The `@events` registry below colocates four facts per event:

    * the **struct module** (e.g. `NodeRegistered`)
    * the **wire-format event type** string (e.g. `"edge.node.registered"`)
    * a one-line **description** of when the event fires
    * a sample **data payload** for documentation and the AsyncAPI spec

  Everything else is derived from this list at compile time:
  `all_event_types/0`, `event_type/1`, `description/1`, `data_example/1`,
  `list_with_descriptions/0`, `lookup/1`. The AsyncAPI spec generator
  reads through the same accessors. Compile-time assertions reject
  duplicate type strings and missing modules.

  Callers construct the appropriate struct and pass it to
  `EdgeAdmin.Events.publish/1`:

      Events.publish(%Catalog.NodeRegistered{node: node})
      Events.publish(%Catalog.NodeStatusChanged{node: node, previous_status: :healthy})

  Field shapes vary per event — see each `defmodule` below for
  `@enforce_keys`, `defstruct`, and the typespec.

  ## Adding a new event

    1. Define the struct module with `@enforce_keys`, `defstruct`, and a
       `@type t` typespec.
    2. Add an entry to `@events` with the module, type string, description,
       and a sample `data` payload (the wire shape an external subscriber
       would see).
    3. Add a `to_data/1` clause that builds the wire payload from the
       struct (field extraction, atom-to-string conversion, etc.).
    4. The AsyncAPI spec, MCP tools, and webhook validation pick up the
       new event automatically.
  """

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  # ---------------------------------------------------------------------------
  # Enrollment key event structs
  # ---------------------------------------------------------------------------

  defmodule EnrollmentKeyVerified do
    @moduledoc false
    @enforce_keys [:result]
    defstruct [:enrollment_key, :result, :attempted_key_blob]

    @type result ::
            :verified
            | :invalid_key
            | :key_expired
            | :key_spent
            | :node_limit_reached

    @type t :: %__MODULE__{
            enrollment_key: EnrollmentKey.t() | nil,
            result: result(),
            attempted_key_blob: String.t() | nil
          }
  end

  # ---------------------------------------------------------------------------
  # Node event structs
  # ---------------------------------------------------------------------------

  defmodule NodeRegistered do
    @moduledoc false
    @enforce_keys [:node]
    defstruct [:node]
    @type t :: %__MODULE__{node: Node.t()}
  end

  defmodule NodeReregistered do
    @moduledoc false
    @enforce_keys [:node]
    defstruct [:node]
    @type t :: %__MODULE__{node: Node.t()}
  end

  defmodule NodeVersionChanged do
    @moduledoc false
    @enforce_keys [:node, :previous_version]
    defstruct [:node, :previous_version]
    @type t :: %__MODULE__{node: Node.t(), previous_version: String.t() | nil}
  end

  defmodule NodeStatusChanged do
    @moduledoc false
    @enforce_keys [:node, :previous_status]
    defstruct [:node, :previous_status]
    @type t :: %__MODULE__{node: Node.t(), previous_status: Node.status()}
  end

  defmodule NodeUpdateTriggered do
    @moduledoc false
    @enforce_keys [:node, :self_update_request_id]
    defstruct [:node, :self_update_request_id]
    @type t :: %__MODULE__{node: Node.t(), self_update_request_id: String.t()}
  end

  # ---------------------------------------------------------------------------
  # Command execution event structs
  # ---------------------------------------------------------------------------

  defmodule CommandExecutionCreated do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule CommandExecutionSent do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule CommandExecutionCompleted do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule CommandExecutionCancelled do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule CommandExecutionExpired do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule CommandExecutionPruned do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  # ---------------------------------------------------------------------------
  # SSH event structs
  # ---------------------------------------------------------------------------

  defmodule SshUsernameVerified do
    @moduledoc false
    @enforce_keys [:node_id, :attempted_username, :auth_method, :result]
    defstruct [:ssh_username, :node_id, :attempted_username, :auth_method, :result]

    @type auth_method :: :password | :public_key | :unknown
    @type result :: :success | :failure

    @type t :: %__MODULE__{
            ssh_username: SshUsername.t() | nil,
            node_id: String.t(),
            attempted_username: String.t(),
            auth_method: auth_method(),
            result: result()
          }
  end

  # ---------------------------------------------------------------------------
  # Self-update event structs
  # ---------------------------------------------------------------------------

  defmodule SelfUpdateCompleted do
    @moduledoc false
    @enforce_keys [:request]
    defstruct [:request]
    @type t :: %__MODULE__{request: SelfUpdateRequest.t()}
  end

  # ---------------------------------------------------------------------------
  # Registry — one entry per event. Order is the catalog's canonical order.
  #
  # Sample data uses string keys / wire-format values: this is the shape an
  # external subscriber sees in `data` after `to_data/1` runs.
  # ---------------------------------------------------------------------------

  @node_base_data %{
    "node_id" => "node-abc123",
    "cluster_name" => "prod",
    "status" => "healthy",
    "version" => "1.2.0",
    "id_type" => "persistent",
    "http_port" => 44_000,
    "ssh_port" => 40_022,
    "host_metrics_port" => 9100,
    "wireguard_metrics_port" => 9101,
    "http_proxy_port" => 44_001,
    "socks5_proxy_port" => 44_002,
    "self_update_enabled" => true,
    "last_seen_at" => "2026-04-13T10:00:00Z",
    "inserted_at" => "2026-04-13T09:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  @execution_base_data %{
    "command_execution_id" => "cmdexec-abc123",
    "command_id" => "cmd-xyz789",
    "node_id" => "node-abc123",
    "cluster_name" => "prod",
    "command_text" => "systemctl restart app",
    "timeout" => 30_000,
    "target_all" => false,
    "expired_at" => nil,
    "inserted_at" => "2026-04-13T10:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  @self_update_base_data %{
    "self_update_request_id" => "selfupd-abc123",
    "targeting" => %{
      "type" => "clusters",
      "cluster_filters" => %{},
      "node_filters" => %{"version" => "1.1.*"}
    },
    "inserted_at" => "2026-04-13T10:00:00Z",
    "updated_at" => "2026-04-13T10:00:00Z"
  }

  @events [
    %{
      module: EnrollmentKeyVerified,
      type: "edge.enrollment_key.verified",
      description: "Agent attempted to enroll using an enrollment key (success or failure).",
      data_example: %{
        "enrollment_key_id" => "enrkey-abc123",
        "cluster_name" => "prod",
        "name" => "prod rollout",
        "uses_remaining" => 4,
        "result" => "verified",
        "verified_at" => "2026-04-13T10:00:00Z"
      }
    },
    %{
      module: NodeRegistered,
      type: "edge.node.registered",
      description: "Node registered for the first time.",
      data_example: @node_base_data
    },
    %{
      module: NodeReregistered,
      type: "edge.node.reregistered",
      description: "Node re-enrolled (reboot, redeploy, etc.).",
      data_example: Map.put(@node_base_data, "status", "healthy")
    },
    %{
      module: NodeVersionChanged,
      type: "edge.node.version_changed",
      description: "Node version changed alongside re-enrollment.",
      data_example: Map.put(@node_base_data, "previous_version", "1.1.0")
    },
    %{
      module: NodeStatusChanged,
      type: "edge.node.status_changed",
      description: "Node health status transitioned.",
      data_example: Map.merge(@node_base_data, %{"status" => "unhealthy", "previous_status" => "healthy"})
    },
    %{
      module: NodeUpdateTriggered,
      type: "edge.node.update_triggered",
      description: "Self-update signal sent to this node.",
      data_example: Map.put(@node_base_data, "self_update_request_id", "selfupd-abc123")
    },
    %{
      module: CommandExecutionCreated,
      type: "edge.command_execution.created",
      description: "Execution record created and queued.",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "pending",
          "exit_code" => nil,
          "sent_at" => nil,
          "completed_at" => nil,
          "cancelled_at" => nil
        })
    },
    %{
      module: CommandExecutionSent,
      type: "edge.command_execution.sent",
      description: "Execution delivered to agent and ACKed.",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "sent",
          "exit_code" => nil,
          "sent_at" => "2026-04-13T10:00:01Z",
          "completed_at" => nil,
          "cancelled_at" => nil
        })
    },
    %{
      module: CommandExecutionCompleted,
      type: "edge.command_execution.completed",
      description: "Agent reported result.",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "completed",
          "exit_code" => 0,
          "sent_at" => "2026-04-13T10:00:01Z",
          "completed_at" => "2026-04-13T10:00:03Z",
          "cancelled_at" => nil
        })
    },
    %{
      module: CommandExecutionCancelled,
      type: "edge.command_execution.cancelled",
      description: "Execution cancelled (explicit or SIGTERM).",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "cancelled",
          "exit_code" => 143,
          "sent_at" => "2026-04-13T10:00:01Z",
          "completed_at" => nil,
          "cancelled_at" => "2026-04-13T10:00:05Z"
        })
    },
    %{
      module: CommandExecutionExpired,
      type: "edge.command_execution.expired",
      description: "Execution swept as stale before running.",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "expired",
          "exit_code" => nil,
          "sent_at" => nil,
          "completed_at" => nil,
          "cancelled_at" => nil,
          "expired_at" => "2026-04-13T10:05:00Z"
        })
    },
    %{
      module: CommandExecutionPruned,
      type: "edge.command_execution.pruned",
      description: "Execution reaped by background pruning worker.",
      data_example:
        Map.merge(@execution_base_data, %{
          "status" => "completed",
          "exit_code" => 0,
          "sent_at" => "2026-04-13T10:00:01Z",
          "completed_at" => "2026-04-13T10:00:03Z",
          "cancelled_at" => nil
        })
    },
    %{
      module: SshUsernameVerified,
      type: "edge.ssh_username.verified",
      description: "Agent verified an SSH credential against admin (success or failure).",
      data_example: %{
        "ssh_username_id" => "sshuser-abc123",
        "node_id" => "node-abc123",
        "cluster_name" => "prod",
        "username" => "deploy",
        "auth_method" => "public_key",
        "result" => "success",
        "verified_at" => "2026-04-13T10:00:00Z"
      }
    },
    %{
      module: SelfUpdateCompleted,
      type: "edge.self_update_request.completed",
      description: "Self-update batch finished.",
      data_example:
        Map.merge(@self_update_base_data, %{
          "status" => "completed",
          "summary" => %{"total" => 10, "triggered" => 9, "failed" => 1}
        })
    }
  ]

  # Compile-time invariants on the registry. Each fires at compile time, before
  # any test runs — so a botched copy-paste shows up in the build, not at runtime.
  @all_types Enum.map(@events, & &1.type)
  if length(@all_types) != length(Enum.uniq(@all_types)) do
    raise "EdgeAdmin.Events.Catalog: duplicate event type in @events"
  end

  @descriptions Map.new(@events, &{&1.type, &1.description})
  @data_examples Map.new(@events, &{&1.type, &1.data_example})

  # ---------------------------------------------------------------------------
  # Public API — derived from @events
  # ---------------------------------------------------------------------------

  @doc """
  Returns every event type currently in the catalog as a list of strings.

  Used by webhook filter validation to reject patterns that match no current
  event type (catches typos at API time).
  """
  @spec all_event_types() :: [String.t()]
  def all_event_types, do: @all_types

  @doc """
  Returns a one-line description of when the given event fires. Returns
  `nil` if the event type is not in the catalog.
  """
  @spec description(String.t()) :: String.t() | nil
  def description(event_type) when is_binary(event_type), do: Map.get(@descriptions, event_type)

  @doc """
  Returns a sample CloudEvents `data` map for the given event type. Useful
  for documentation, examples, and orienting the model on payload shape.
  Returns `nil` if the event type is not in the catalog.
  """
  @spec data_example(String.t()) :: map() | nil
  def data_example(event_type) when is_binary(event_type), do: Map.get(@data_examples, event_type)

  @doc """
  Aggregates everything known about an event type into a single map:

      %{
        type: "edge.node.registered",
        description: "Node registered for the first time.",
        data_example: %{...},
        reference: "/asyncdoc"
      }

  Returns `{:error, :not_found}` if the event type is not in the catalog.
  """
  @spec lookup(String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup(event_type) when is_binary(event_type) do
    if event_type in @all_types do
      {:ok,
       %{
         type: event_type,
         description: description(event_type),
         data_example: data_example(event_type),
         reference: "/asyncdoc"
       }}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns a list of `%{type, description}` maps — one per known event
  type, in catalog order. Useful for browsing the catalog without
  pulling each event's full payload example.
  """
  @spec list_with_descriptions() :: [map()]
  def list_with_descriptions do
    Enum.map(@events, fn e -> %{type: e.type, description: e.description} end)
  end

  @doc "Returns the string event type for the given event struct."
  @spec event_type(term()) :: String.t()
  for entry <- @events do
    def event_type(%unquote(entry.module){}), do: unquote(entry.type)
  end

  @doc "Builds the `data` map for the event envelope."
  @spec to_data(term()) :: map()

  # Enrollment key events
  def to_data(%EnrollmentKeyVerified{} = event), do: enrollment_key_verified_data(event)

  # Node events — base snapshot, then overlay any extra fields
  def to_data(%NodeRegistered{node: node}), do: node_data(node)
  def to_data(%NodeReregistered{node: node}), do: node_data(node)

  def to_data(%NodeVersionChanged{node: node, previous_version: prev}) do
    node |> node_data() |> Map.put("previous_version", prev)
  end

  def to_data(%NodeStatusChanged{node: node, previous_status: prev}) do
    node |> node_data() |> Map.put("previous_status", Atom.to_string(prev))
  end

  def to_data(%NodeUpdateTriggered{node: node, self_update_request_id: req_id}) do
    node |> node_data() |> Map.put("self_update_request_id", req_id)
  end

  # Command execution events — base snapshot (output excluded)
  def to_data(%CommandExecutionCreated{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%CommandExecutionSent{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%CommandExecutionCompleted{execution: ex, command: cmd, cluster_name: cn}),
    do: execution_data(ex, cmd, cn)

  def to_data(%CommandExecutionCancelled{execution: ex, command: cmd, cluster_name: cn}),
    do: execution_data(ex, cmd, cn)

  def to_data(%CommandExecutionExpired{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%CommandExecutionPruned{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  # SSH events
  def to_data(%SshUsernameVerified{} = event), do: ssh_username_verified_data(event)

  # Self-update events
  def to_data(%SelfUpdateCompleted{request: req}), do: self_update_data(req)

  # ---------------------------------------------------------------------------
  # Data builders — full object snapshots, no internal/secret fields
  # ---------------------------------------------------------------------------

  # The `key` blob is intentionally excluded from the event — it's a credential.
  # On `:invalid_key` the enrollment_key is nil (no DB row matched); the other
  # identifying fields fall back to nil too.
  defp enrollment_key_verified_data(%EnrollmentKeyVerified{enrollment_key: nil, result: result}) do
    %{
      "enrollment_key_id" => nil,
      "cluster_name" => nil,
      "name" => nil,
      "uses_remaining" => nil,
      "result" => Atom.to_string(result),
      "verified_at" => format_dt(DateTime.utc_now())
    }
  end

  defp enrollment_key_verified_data(%EnrollmentKeyVerified{enrollment_key: key, result: result}) do
    %{
      "enrollment_key_id" => key.id,
      "cluster_name" => cluster_name(key),
      "name" => key.name,
      "uses_remaining" => key.uses_remaining,
      "result" => Atom.to_string(result),
      "verified_at" => format_dt(DateTime.utc_now())
    }
  end

  defp node_data(node) do
    %{
      "node_id" => node.id,
      "cluster_name" => cluster_name(node),
      "status" => Atom.to_string(node.status),
      "version" => node.version,
      "id_type" => Atom.to_string(node.id_type),
      "http_port" => node.http_port,
      "ssh_port" => node.ssh_port,
      "host_metrics_port" => node.host_metrics_port,
      "wireguard_metrics_port" => node.wireguard_metrics_port,
      "http_proxy_port" => node.http_proxy_port,
      "socks5_proxy_port" => node.socks5_proxy_port,
      "self_update_enabled" => node.self_update_enabled,
      "last_seen_at" => format_dt(node.last_seen_at),
      "inserted_at" => format_dt(node.inserted_at),
      "updated_at" => format_dt(node.updated_at)
    }
  end

  defp execution_data(execution, command, cluster_name) do
    %{
      "command_execution_id" => execution.id,
      "command_id" => execution.command_id,
      "node_id" => execution.node_id,
      "cluster_name" => cluster_name,
      "command_text" => command.command_text,
      "timeout" => command.timeout,
      "status" => Atom.to_string(execution.status),
      "exit_code" => execution.exit_code,
      "target_all" => execution.target_all,
      "expired_at" => format_dt(command.expired_at),
      "sent_at" => format_dt(execution.sent_at),
      "completed_at" => format_dt(execution.completed_at),
      "cancelled_at" => format_dt(execution.cancelled_at),
      "inserted_at" => format_dt(execution.inserted_at),
      "updated_at" => format_dt(execution.updated_at)
    }
  end

  # `password_hash` and the public-key strings are never echoed back. We carry
  # only the verification decision and identifying metadata. `ssh_username` is
  # nil when the username doesn't exist for the node (still fired, since failed
  # attempts against missing usernames are real security signal).
  defp ssh_username_verified_data(%SshUsernameVerified{
         ssh_username: nil,
         node_id: node_id,
         attempted_username: attempted,
         auth_method: auth_method,
         result: result
       }) do
    %{
      "ssh_username_id" => nil,
      "node_id" => node_id,
      "cluster_name" => nil,
      "username" => attempted,
      "auth_method" => Atom.to_string(auth_method),
      "result" => Atom.to_string(result),
      "verified_at" => format_dt(DateTime.utc_now())
    }
  end

  defp ssh_username_verified_data(%SshUsernameVerified{
         ssh_username: ssh_username,
         node_id: node_id,
         attempted_username: attempted,
         auth_method: auth_method,
         result: result
       }) do
    %{
      "ssh_username_id" => ssh_username.id,
      "node_id" => node_id,
      "cluster_name" => ssh_username_cluster_name(ssh_username),
      "username" => attempted,
      "auth_method" => Atom.to_string(auth_method),
      "result" => Atom.to_string(result),
      "verified_at" => format_dt(DateTime.utc_now())
    }
  end

  defp self_update_data(request) do
    %{
      "self_update_request_id" => request.id,
      "status" => Atom.to_string(request.status),
      "targeting" => request.targeting,
      "summary" => request.summary,
      "inserted_at" => format_dt(request.inserted_at),
      "updated_at" => format_dt(request.updated_at)
    }
  end

  defp ssh_username_cluster_name(%{node: %{cluster: %{name: name}}}), do: name
  defp ssh_username_cluster_name(_), do: nil

  defp cluster_name(%{cluster: %{name: name}}), do: name
  defp cluster_name(_), do: nil

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
end
