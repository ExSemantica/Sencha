defmodule Sencha.Administration do
  @moduledoc """
  Utilities for administering IRC
  """

  @doc """
  Convenience for `Sencha.UserSupervisor.broadcast_wallops/1`.
  """
  def broadcast_wallops(message) do
    Sencha.UserSupervisor.broadcast_wallops(message)
  end
end
