defmodule Sencha.TCP do
  @moduledoc """
  TCP socket. This uses `:gen_tcp`. This is organized by:
  - `Sencha.TCP.Server`: the TCP server application itself
  - `Sencha.TCP.Client`: the client process
  - `Sencha.TCP.Supervisor`: allows everything to crash when server crashes
  - `Sencha.TCP.ClientPool`: allows the clients to stay when one client crashes
  """
end
