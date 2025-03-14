defmodule Sencha.Administration do
  @moduledoc """
  Utilities for administering IRC
  """
  def broadcast_wallops(message) do
    Sencha.UserSupervisor.broadcast_wallops(message)
  end
end
