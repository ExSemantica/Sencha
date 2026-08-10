# Application startup
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Sencha.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    Sencha.init_creation_date()
    Sencha.refresh_version()
    Sencha.rehash()

    # Start mnesia because IRC channels depend on it for distributed state

    # We don't create the schema, we just need to include on-disk nodes
    # which we don't need
    :mnesia.start()

    channel =
      :mnesia.create_table(Sencha.Channel.Roster,
        attributes: [:channel, :targets, :attributes, :modes],
        ram_copies: [node() | Node.list()],
        type: :set
      )

    :ok =
      case channel do
        {:atomic, :ok} ->
          Logger.info("Started new IRC channel roster")
          :ok

        {:aborted, {:already_exists, _tid}} ->
          Logger.info("Importing IRC channel roster from other node(s)")
          :mnesia.wait_for_tables([Sencha.Channel.Roster], 5000)
      end

    children = [
      Sencha.Repo,
      Sencha.KLine,
      {ThousandIsland,
       supervisor_options: [name: Sencha.Supervisor.User], port: 6667, handler_module: Sencha.User}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sencha.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(_changed, _new, _removed) do
    Sencha.refresh_version()
  end
end
