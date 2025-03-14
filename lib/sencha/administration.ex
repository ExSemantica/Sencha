defmodule Sencha.Administration do
  @moduledoc """
  Utilities for administering IRC
  """

  @doc """
  Convenience for `Sencha.UserSupervisor.broadcast_wallops/1`.
  """
  def announce(message) do
    Sencha.UserSupervisor.broadcast_wallops("[Announcement] " <> message)
  end
end
