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
      {ThousandIsland, port: 6667, handler_module: Sencha.Handler},
      Sencha.Repo
    ]

    :persistent_term.put(Sencha.Application.Started, DateTime.utc_now(:second))

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sencha.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
