defmodule Sencha.User.State do
  @moduledoc """
  Stores state of a `Sencha.User`.
  """
  @enforce_keys ~w(handler_process rdns_host timeout_ping last_ping_from_server modes nickname)a

  defstruct [
    :handler_process,
    :rdns_host,
    :timeout_ping,
    :timeout_ping_hard,
    :timeout_operator,
    :last_ping_from_server,
    :modes,
    :nickname
  ]

  @doc """
  Convenience for initializing a hostmask.
  """
  def hostmask(%__MODULE__{nickname: nickname, rdns_host: host}) do
    "#{nickname}!~Sencha@#{host}"
  end
end
