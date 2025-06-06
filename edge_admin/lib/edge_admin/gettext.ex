# edge_admin/lib/edge_admin/gettext.ex
defmodule EdgeAdmin.Gettext do
  @moduledoc """
  This module manages everything related to the translations used in the
  application.
  """

  use Gettext.Backend, otp_app: :edge_admin
end
