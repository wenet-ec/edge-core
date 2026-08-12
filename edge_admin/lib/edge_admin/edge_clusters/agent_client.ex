# edge_admin/lib/edge_admin/edge_clusters/agent_client.ex
defmodule EdgeAdmin.EdgeClusters.AgentClient do
  @moduledoc """
  HTTP client for all admin → agent communication.

  Every outbound call from the admin to an agent's HTTP API lives here.
  No other module should make direct `Req` calls to agent endpoints.

  All functions accept a `Node` struct and derive the URL from `vpn_hostname`
  and `http_port`. Authentication uses `node.api_token` where required.

  Covers health checks, command delivery/cancellation, diagnostics,
  self-update triggers, and the three metrics surfaces.
  """

  alias EdgeAdmin.Nodes.Schemas.Node

  require Logger

  @doc "Returns the timeout used for command delivery and cancellation calls."
  @spec command_call_timeout() :: pos_integer()
  def command_call_timeout, do: command_delivery_timeout() + 2_000

  @doc "Returns the timeout used for metrics scraping calls."
  @spec metrics_call_timeout() :: pos_integer()
  def metrics_call_timeout, do: metrics_scrape_timeout() + 2_000

  @doc "Returns the timeout used for Agent health checks."
  @spec health_check_call_timeout() :: pos_integer()
  def health_check_call_timeout, do: health_check_timeout() + 500

  @doc "Returns the timeout used for diagnostic collection calls."
  @spec diagnostics_call_timeout() :: pos_integer()
  def diagnostics_call_timeout, do: health_check_timeout() + 2_000

  defp command_delivery_timeout, do: Application.get_env(:edge_admin, :command_delivery_timeout, 10_000)

  defp metrics_scrape_timeout, do: Application.get_env(:edge_admin, :metrics_scrape_timeout, 10_000)

  defp health_check_timeout, do: Application.get_env(:edge_admin, :health_check_timeout, 5_000)

  defp command_opts do
    t = command_delivery_timeout()
    [receive_timeout: t, connect_options: [timeout: t], retry: false]
  end

  defp metrics_opts do
    t = metrics_scrape_timeout()
    [receive_timeout: t, connect_options: [timeout: t], retry: false]
  end

  defp health_check_opts do
    t = health_check_timeout()
    [receive_timeout: t, connect_options: [timeout: t], retry: false]
  end

  defp diagnostics_opts do
    t = diagnostics_call_timeout()
    [receive_timeout: t, connect_options: [timeout: t], retry: false]
  end

  defp agent_base_url(%Node{} = node, port \\ nil) do
    port = port || node.http_port
    "http://#{Node.vpn_hostname(node)}:#{port}"
  end

  # Health

  @doc """
  Pings the agent health endpoint.

  Returns `:healthy`, `:unhealthy`, or `:unreachable`.
  """
  @spec ping(Node.t()) :: :healthy | :unhealthy | :unreachable
  def ping(%Node{} = node) do
    url = agent_base_url(node) <> "/health"

    case Req.get(url, health_check_opts()) do
      {:ok, %{status: 200}} -> :healthy
      {:ok, %{status: 503}} -> :unhealthy
      _ -> :unreachable
    end
  rescue
    _ -> :unreachable
  catch
    _, _ -> :unreachable
  end

  @doc """
  Requests a diagnostic report from an Agent over its VPN URL.
  """
  @spec get_diagnostics(Node.t()) :: {:ok, map()} | {:error, term()}
  def get_diagnostics(%Node{} = node) do
    url = agent_base_url(node) <> "/api/v1/diagnostics"
    opts = Keyword.merge([auth: {:bearer, node.api_token}], diagnostics_opts())

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: %{"data" => report}}} when is_map(report) -> {:ok, report}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # Commands

  @doc """
  Delivers a command execution payload to the agent.

  Returns `{:ok, :sent}` on any 2xx, `{:error, reason}` otherwise.
  """
  @spec deliver_execution(Node.t(), map()) :: {:ok, :sent} | {:error, term()}
  def deliver_execution(%Node{} = node, execution_data) do
    url = agent_base_url(node) <> "/api/v1/command_executions"
    opts = Keyword.merge([json: execution_data, auth: {:bearer, node.api_token}], command_opts())

    case Req.post(url, opts) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :sent}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("deliver_execution failed for node #{node.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a cancellation request for a command execution to the agent.

  Returns `:ok` on any 2xx, `{:error, reason}` otherwise.
  """
  @spec cancel_execution(Node.t(), binary()) :: :ok | {:error, term()}
  def cancel_execution(%Node{} = node, execution_id) do
    url = agent_base_url(node) <> "/api/v1/command_executions/#{execution_id}/cancel"

    opts = Keyword.merge([auth: {:bearer, node.api_token}], command_opts())

    case Req.post(url, opts) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("cancel_execution failed for node #{node.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Self-update

  @doc """
  Triggers a self-update on the agent.

  Returns `:ok` on 202. Connection errors after triggering are treated as
  success (watchtower likely restarted the agent mid-request).
  """
  @spec trigger_self_update(Node.t()) :: :ok | {:error, term()}
  def trigger_self_update(%Node{} = node) do
    url = agent_base_url(node) <> "/api/v1/self_updates/trigger"
    opts = Keyword.merge([auth: {:bearer, node.api_token}], command_opts())

    case Req.post(url, opts) do
      {:ok, %{status: 202}} ->
        :ok

      {:ok, %{status: 403}} ->
        {:error, :self_update_disabled}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %Req.TransportError{reason: reason} = error} ->
        Logger.debug("trigger_self_update transport error (likely agent restarted): #{inspect(error)}")

        if reason in [:timeout, :econnrefused, :closed] do
          :ok
        else
          {:error, error}
        end

      {:error, reason} ->
        Logger.debug("trigger_self_update failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Metrics scraping

  @doc """
  Scrapes Node Exporter host metrics from the agent's host metrics port.
  Returns `{:ok, metrics_text}` or `{:error, reason}`.
  """
  @spec scrape_host_metrics(Node.t()) :: {:ok, String.t()} | {:error, term()}
  def scrape_host_metrics(%Node{} = node) do
    url = agent_base_url(node, node.host_metrics_port) <> "/metrics"

    case Req.get(url, metrics_opts()) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Scrapes agent application metrics from the PromEx endpoint.
  Returns `{:ok, metrics_text}` or `{:error, reason}`.
  """
  @spec scrape_agent_metrics(Node.t()) :: {:ok, String.t()} | {:error, term()}
  def scrape_agent_metrics(%Node{} = node) do
    url = agent_base_url(node) <> "/api/v1/agents/me/metrics/raw"
    opts = Keyword.merge([auth: {:bearer, node.api_token}], metrics_opts())

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Scrapes WireGuard metrics from the agent's WireGuard exporter port.
  Returns `{:ok, metrics_text}` or `{:error, reason}`.
  """
  @spec scrape_wireguard_metrics(Node.t()) :: {:ok, String.t()} | {:error, term()}
  def scrape_wireguard_metrics(%Node{} = node) do
    url = agent_base_url(node, node.wireguard_metrics_port) <> "/metrics"

    case Req.get(url, metrics_opts()) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
