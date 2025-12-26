# edge_agent/lib/edge_agent/prom_ex/edge_agent_plugin.ex
defmodule EdgeAgent.PromEx.EdgeAgentPlugin do
  @moduledoc """
  Custom PromEx plugin for edge_agent specific metrics.

  Provides business-level metrics for:
  - Command execution (syncing, running, reporting)
  - Bootstrap process (agent registration)
  - Admin discovery (finding assigned admin)
  - Proxy server (HTTP/SOCKS5 connections)
  - SSH server (session management)
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :edge_agent_event_metrics,
      [
        # Bootstrap metrics
        counter(
          [:edge_agent, :bootstrap, :registration, :total],
          event_name: [:edge_agent, :bootstrap, :registration],
          description: "Total number of agent registration attempts",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        distribution(
          [:edge_agent, :bootstrap, :registration, :duration, :milliseconds],
          event_name: [:edge_agent, :bootstrap, :registration],
          description: "Duration of agent registration in milliseconds",
          measurement: :duration,
          tags: [:status],
          tag_values: &get_status_tag/1,
          reporter_options: [
            buckets: [100, 500, 1_000, 2_000, 5_000, 10_000]
          ]
        ),

        # Admin discovery metrics
        counter(
          [:edge_agent, :discovery, :admin, :found, :total],
          event_name: [:edge_agent, :discovery, :admin, :found],
          description: "Total number of successful admin discoveries",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),

        # Command sync metrics
        counter(
          [:edge_agent, :commands, :sync, :total],
          event_name: [:edge_agent, :commands, :sync],
          description: "Total number of command sync attempts with admin",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        last_value(
          [:edge_agent, :commands, :sync, :fetched_count],
          event_name: [:edge_agent, :commands, :sync],
          description: "Number of command executions fetched in last sync",
          measurement: :count
        ),

        # Command execution metrics
        counter(
          [:edge_agent, :commands, :execution, :enqueued, :total],
          event_name: [:edge_agent, :commands, :execution, :enqueued],
          description: "Total number of command executions enqueued",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        counter(
          [:edge_agent, :commands, :execution, :completed, :total],
          event_name: [:edge_agent, :commands, :execution, :completed],
          description: "Total number of command executions completed",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        distribution(
          [:edge_agent, :commands, :execution, :duration, :milliseconds],
          event_name: [:edge_agent, :commands, :execution, :completed],
          description: "Duration of command executions in milliseconds",
          measurement: :duration,
          tags: [:result],
          tag_values: &get_result_tag/1,
          reporter_options: [
            buckets: [100, 500, 1_000, 5_000, 10_000, 30_000, 60_000]
          ]
        ),
        last_value(
          [:edge_agent, :commands, :execution, :exit_code],
          event_name: [:edge_agent, :commands, :execution, :completed],
          description: "Exit code of last command execution",
          measurement: :exit_code
        ),

        # Command reporting metrics
        counter(
          [:edge_agent, :commands, :report, :total],
          event_name: [:edge_agent, :commands, :report],
          description: "Total number of command result reports to admin",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        last_value(
          [:edge_agent, :commands, :report, :batch_size],
          event_name: [:edge_agent, :commands, :report],
          description: "Number of executions reported in last batch",
          measurement: :batch_size
        ),

        # Proxy server metrics
        counter(
          [:edge_agent, :proxy, :http, :connection, :total],
          event_name: [:edge_agent, :proxy, :http, :connection],
          description: "Total HTTP proxy connections",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        counter(
          [:edge_agent, :proxy, :socks5, :connection, :total],
          event_name: [:edge_agent, :proxy, :socks5, :connection],
          description: "Total SOCKS5 proxy connections",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        distribution(
          [:edge_agent, :proxy, :session, :duration, :milliseconds],
          event_name: [:edge_agent, :proxy, :session, :duration],
          description: "Duration of proxy sessions in milliseconds",
          measurement: :duration,
          tags: [:protocol],
          tag_values: &get_protocol_tag/1,
          reporter_options: [
            buckets: [1_000, 5_000, 10_000, 30_000, 60_000, 300_000, 600_000]
          ]
        ),

        # SSH server metrics
        counter(
          [:edge_agent, :ssh, :connection, :total],
          event_name: [:edge_agent, :ssh, :connection],
          description: "Total SSH connection attempts",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        counter(
          [:edge_agent, :ssh, :authentication, :total],
          event_name: [:edge_agent, :ssh, :authentication],
          description: "Total SSH authentication attempts",
          tags: [:username, :auth_method, :result],
          tag_values: &get_ssh_auth_tags/1
        ),
        distribution(
          [:edge_agent, :ssh, :session, :duration, :milliseconds],
          event_name: [:edge_agent, :ssh, :session, :duration],
          description: "Duration of SSH sessions in milliseconds",
          measurement: :duration,
          reporter_options: [
            buckets: [1_000, 5_000, 10_000, 30_000, 60_000, 300_000, 600_000]
          ]
        ),

        # Discovery worker metrics
        counter(
          [:edge_agent, :discovery, :scan, :total],
          event_name: [:edge_agent, :discovery, :scan],
          description: "Total number of periodic discovery scans",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        last_value(
          [:edge_agent, :discovery, :admins_found],
          event_name: [:edge_agent, :discovery, :scan],
          description: "Number of admins found in last discovery scan",
          measurement: :admins_found
        )
      ]
    )
  end

  # Tag extraction functions
  defp get_status_tag(%{status: status}) do
    %{status: to_string(status)}
  end

  defp get_result_tag(%{result: result}) do
    %{result: to_string(result)}
  end

  defp get_protocol_tag(%{protocol: protocol}) do
    %{protocol: to_string(protocol)}
  end

  defp get_ssh_auth_tags(%{username: username, auth_method: auth_method, result: result}) do
    %{username: to_string(username), auth_method: to_string(auth_method), result: to_string(result)}
  end
end
