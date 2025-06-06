# edge_agent/lib/edge_agent/gettext.ex
defmodule EdgeAgent.Gettext do
  @moduledoc """
  This module manages everything related to the translations used in the
  application.
  """

  use Gettext.Backend, otp_app: :edge_agent
end
