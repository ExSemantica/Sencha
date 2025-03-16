defmodule Sencha.Administration do
  @moduledoc """
  Utilities for administering IRC
  """

  @doc """
  Convenience to broadcast a message to all users with mode +w in this server.
  """
  def wallops(message) do
    Sencha.UserPool.all()
    |> Enum.map(fn username ->
      case Registry.lookup(Sencha.UserRegistry, username) do
        [{user_pid, _}] -> Sencha.User.wallops(user_pid, message)
        [] -> :ok
      end
    end)

    :ok
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
