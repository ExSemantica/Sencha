defmodule Sencha.TCP.ClientPool do
  use DynamicSupervisor
  require Logger

  @doc """
  Starts the client TCP pool.
  """
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, [args], name: __MODULE__)
  end

  def start_child(args) do
    DynamicSupervisor.start_child(__MODULE__, {Sencha.TCP.Client, args})
  end

  @impl DynamicSupervisor
  def init(max_clients: max_clients) do
    Logger.debug("Starting TCP client pool with #{max_clients} max clients")
    DynamicSupervisor.init(strategy: :one_for_one, max_children: max_clients)
  end
end
