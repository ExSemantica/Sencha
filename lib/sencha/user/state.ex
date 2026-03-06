defmodule Sencha.User.State do
  @moduledoc """
  Stores state of a `Sencha.User`.

  - `:handler_process`: The `Sencha.Handler` we are using
  - `:rdns_host`: The reverse DNS hostname
  - `:timeout_ping`: A timer for PING events
  - `:timeout_ping_hard`: A timer to disconnect the user if they don't PONG
  - `:timeout_operator`: A timer for removing OPER privileges
  - `:last_ping_from_server`: A `DateTime` of the last PING from the server
  - `:modes`: A `MapSet` of this user's MODEs
  - `:nickname`: The nickname assigned to this user
  - `:channel_names`: Channels this user is in
  """
  @enforce_keys ~w(handler_process rdns_host timeout_ping last_ping_from_server modes nickname channel_names)a

  defstruct [
    :handler_process,
    :rdns_host,
    :timeout_ping,
    :timeout_ping_hard,
    :timeout_operator,
    :last_ping_from_server,
    :modes,
    :nickname,
    :channel_names
  ]

  @doc """
  Convenience for initializing a hostmask.
  """
  def hostmask(%__MODULE__{nickname: nickname, rdns_host: host}) do
    "#{nickname}!~Sencha@#{host}"
  end
end
