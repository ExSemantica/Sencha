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
  - `:user_process`: After initializing the `Sencha.User`, IRC duties are
    delegated to it.
  - `:timeout_auth`: Kills the client when it doesn't authenticate on time.
  - `:rdns_host`: A `Sencha.Handler.LookupRDNS` result.

  ### Will be migrated to `Sencha.User` later
  - `:timeout_ping`: Waits to send a ping.
  - `:timeout_ping_hard`: Kills the client when it doesn't ping on time.
  - `:last_ping_from_server`: When was the last ping sent?
  - `:timeout_operator`: User is operator until this `DateTime`.
  - `:modes`: A list of IRC modes this user has.
  """
  @enforce_keys ~w(authentication_data authentication_state capabilities)a
  defstruct [
    :authentication_data,
    :authentication_state,
    :nickname,
    :capabilities,
    :user_process,
    :timeout_auth,
    :rdns_host,

    # REMOVE THESE LATER
    # :timeout_ping,
    # :timeout_ping_hard,
    # :timeout_operator,
    # :last_ping_from_server,
    # :modes
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
end
