# Cached K-Line lookup
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
defmodule Sencha.KLine do
  @moduledoc """
  Cached K-Line lookup

  A K-Line stops the user from connecting to the IRC server

  There can be thousands of K-Lines in a network so caching is the smart thing
  to do
  """
  require Logger
  use GenServer

  # ===========================================================================
  # Public API
  # ===========================================================================
  @doc """
  Starts the K-Line manager
  """
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Attempt to insert a K-Line by specific CIDR string and reason

  Returns an identifier
  """
  def push(cidr_string, reason) do
    GenServer.call(__MODULE__, {:push, cidr_string, reason})
  end

  @doc """
  Attempt to remove a K-Line by its identifier
  """
  def pop(id) do
    GenServer.cast(__MODULE__, {:pop, id})
  end

  @doc """
  Checks if this `:inet` formatted IP address is K-Lined
  """
  def klined?(ip_address) do
    GenServer.call(__MODULE__, {:klined?, ip_address})
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @impl GenServer
  def init([]) do
    :ets.new(Sencha.KLine.ETS, [:set, :named_table])

    klines = Sencha.Repo.all(Sencha.Repo.KLine)

    for %Sencha.Repo.KLine{id: id, cidr: cidr, reason: reason} <- klines do
      case cidr |> InetCidr.parse_cidr() do
        {:ok, cidr_parsed} ->
          :ets.insert(Sencha.KLine.ETS, {id, cidr_parsed, reason})

        {:error, error} ->
          Logger.warning("K-Line manager invalid entry ##{id} (#{error.message})")
      end
    end

    Logger.info(
      "K-Line manager started with #{Sencha.Repo.aggregate(Sencha.Repo.KLine, :count)} entries"
    )

    {:ok, []}
  end

  @impl GenServer
  def handle_call({:push, cidr_string, reason}, _from, state) do
    case cidr_string |> InetCidr.parse_cidr() do
      {:ok, cidr_parsed} ->
        case Sencha.Repo.insert(%Sencha.Repo.KLine{cidr: cidr_string, reason: reason}) do
          {:ok, %Sencha.Repo.KLine{id: id}} ->
            :ets.insert(Sencha.KLine.ETS, {id, cidr_parsed, reason})

            for user <- Sencha.Supervisor.User.gather() do
              Sencha.User.check_kline(user, cidr_parsed, id, reason)
            end

            Logger.info(
              "K-Line manager successfully added K-Line #{cidr_string} (##{id}): #{reason}"
            )

            {:reply, {:ok, id}, state}

          {:error, changeset} ->
            {:reply,
             {:error,
              for error <- changeset.errors do
                {_what, {what, _constraint}} = error
                Logger.warning("K-Line manager failed to add K-Line (#{what})")

                error
              end}, state}
        end

      {:error, error} ->
        Logger.warning("K-Line manager failed to add K-Line (#{error.message})")

        {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_call({:klined?, ip_address}, _from, state) do
    {:reply,
     {:ok,
      :ets.foldl(
        fn {id, cidr, reason}, acc ->
          if InetCidr.contains?(cidr, ip_address) and is_nil(acc) do
            {id, reason}
          else
            acc
          end
        end,
        nil,
        Sencha.KLine.ETS
      )}, state}
  end

  @impl GenServer
  def handle_cast({:pop, id}, state) do
    case Sencha.Repo.get(Sencha.Repo.KLine, id) do
      nil ->
        Logger.warning("K-Line manager failed to remove K-Line ##{id} (it does not exist)")

      what ->
        case what |> Sencha.Repo.delete() do
          {:ok, %Sencha.Repo.KLine{cidr: cidr_string}} ->
            :ets.take(Sencha.KLine.ETS, id)
            Logger.info("K-Line manager successfully removed K-Line ##{id} (#{cidr_string})")

          {:error, changeset} ->
            for error <- changeset.errors do
              {_what, {what, _constraint}} = error
              Logger.warning("K-Line manager failed to remove K-Line ##{id} (#{what})")
            end
        end
    end

    {:noreply, state}
  end
end
