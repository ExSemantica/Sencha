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
      Sencha.Repo,
      Sencha.User.Supervisor,
      Sencha.Channel.Supervisor,
      Sencha.Scoreboard
    ]

    # This should not be rehashable
    :persistent_term.put(Sencha.Application.Started, DateTime.utc_now(:second))

    :mnesia.create_schema([node()])
    :mnesia.start()

    Sencha.rehash()

    # Wait a bit then reset this instance's member counts to 0
    Process.send_after(Sencha.Scoreboard, :reset_counters, 5_000)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sencha.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
