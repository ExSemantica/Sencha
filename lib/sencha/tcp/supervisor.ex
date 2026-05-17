defmodule Sencha.TCP.Supervisor do
  @moduledoc """
  The supervisor for the TCP server and the TCP client pool.

  NOTE: The TCP client supervisor is the child of this supervisor.
  """
  use Supervisor
  require Logger

  @doc """
  Starts the main TCP supervisor.
  """
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Supervisor
  def init(port: port, max_clients: max_clients) do
    Logger.debug("Starting TCP main supervisor")

    children = [
      %{
        id: Sencha.TCP.Server,
        start: {Sencha.TCP.Server, :start_link, port: port}
      },
      %{
        id: Sencha.TCP.ClientPool,
        start: {Sencha.TCP.ClientPool, :start_link, max_clients: max_clients}
      }
    ]

    # "One for all", the intention is to crash both the TCP server and all of
    # the clients to prevent zombie clients.
    Supervisor.init(children, strategy: :one_for_all)
  end
end
