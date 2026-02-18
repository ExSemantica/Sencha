defmodule Sencha.Handler.UserState do
  @moduledoc """
  Organizes state of a `Sencha.Handler`.

  - `:authentication_state`: can be the following:
    - `:initialized`: The client needs to initiate a CAP handshake
    - `:waiting_for_capabilties`: The client needs to CAP END a handshake
    with SASL PLAIN enabled.
    - `:waiting_for_authentication`: The client is allowed to start an
    AUTHENTICATE PLAIN request.
    - `:ok`: The client has successfully authenticated.
  - `:authentication_data`: Optionally a binary containing SASL auth data.
  - `:nickname`: The user's IRC nickname.
  - `:capabilities`: A `MapSet` representing IRCv3 capabilities in use.
  - `:timeout_auth`: Kills the client when it doesn't authenticate on time.
  """
  @enforce_keys ~w(authentication_data authentication_state capabilities)a
  defstruct [
    :authentication_data,
    :authentication_state,
    :nickname,
    :capabilities,
    :timeout_auth
  ]

  @doc """
  Convenience for creating new user states.
  """
  def init() do
    %__MODULE__{
      authentication_data: [],
      authentication_state: :initialized,
      capabilities: MapSet.new(),
      timeout_auth:
        Process.send_after(self(), :timeout_auth, Application.fetch_env!(:sencha, :auth_timeout))
    }
  end

  @doc """
  Convenience for initializing a hostmask.
  """
  def hostmask(nickname) do
    "#{nickname}!#{nickname}@user/#{nickname}"
  end
end
