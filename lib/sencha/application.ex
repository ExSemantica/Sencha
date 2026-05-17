defmodule Sencha.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Sencha.Worker.start_link(arg)
      # {Sencha.Worker, arg}
      {Sencha.TCP.Supervisor, port: 6667, max_clients: 128}
    ]

    # Set important constants here
    :persistent_term.put(__MODULE__.Host, Application.get_env(:sencha, :host))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sencha.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
