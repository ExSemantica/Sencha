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

  @doc """
  Convenience to disconnect a username.

  This is case-sensitive.
  """
  def kill(username, message \\ "No reason") do
    case Registry.lookup(Sencha.UserRegistry, username) do
      [{user_pid, _}] -> Sencha.User.kill_connection(user_pid, "Services", message)
      _other -> :error
    end
  end
end
