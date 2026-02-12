defmodule Sencha.Handler.UserState do
  @moduledoc """
  Organizes state of a `Sencha.Handler`.

  - `:authentication_state`: can be the following:
    `:initialized`: The connection needs to initiate a CAP handshake
    `:waiting_for_capabilties`: The connection needs to finish a CAP handshake
    with SASL PLAIN enabled. The SASL credentials must be valid.
    `:ok`: The connection has successfully authenticated.
  """
  @enforce_keys ~w(authentication_state)a
  defstruct [
    :authentication_state
  ]

  @doc """
  Convenience for creating new user states.
  """
  def init() do
    %__MODULE__{authentication_state: :initialized}
  end
end
