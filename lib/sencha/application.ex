defmodule Sencha.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Sencha.ApplicationInfo.refresh()

    # TODO: Distributed Elixir for 2+ IRC nodes
    # TODO: Distributed Elixir for connecting to the ExSemantica gateway?
    # We could use libcluster.
    children = [
      # Starts a worker by calling: Sencha.Worker.start_link(arg)
      # {Sencha.Worker, arg}
      {ThousandIsland, port: 6667, handler_module: Sencha.Handler},
      Sencha.ChannelSupervisor,
      Sencha.UserSupervisor,
      {Registry, keys: :unique, name: Sencha.ChannelRegistry},
      {Registry, keys: :unique, name: Sencha.UserRegistry},
      {Cluster.Supervisor,
       [Application.get_env(:libcluster, :topologies), [name: Sencha.ClusterSupervisor]]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sencha.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
