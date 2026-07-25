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
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Attempt to insert a K-Line by specific CIDR string and reason
  """
  def push(cidr_string, reason) do
    GenServer.cast(__MODULE__, {:push, cidr_string, reason})
  end

  @doc """
  Attempt to remove a K-Line by specific CIDR string
  """
  def pop(cidr_string) do
    GenServer.cast(__MODULE__, {:pop, cidr_string})
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

    for %Sencha.Repo.KLine{cidr: cidr, reason: reason} <- klines do
      {:ok, cidr_parsed} = cidr |> InetCidr.parse_cidr()
      :ets.insert(Sencha.KLine.ETS, {cidr_parsed, reason})
    end

    Logger.info(
      "K-Line manager started with #{Sencha.Repo.aggregate(Sencha.Repo.KLine, :count)} entries"
    )

    {:ok, []}
  end

  @impl GenServer
  def handle_cast({:push, cidr_string, reason}, state) do
    case Sencha.Repo.insert(%Sencha.Repo.KLine{cidr: cidr_string, reason: reason}) do
      {:ok, _} ->
        cidr_parsed = cidr_string |> InetCidr.parse_cidr!()
        :ets.insert(Sencha.KLine.ETS, {cidr_parsed, reason})
        Logger.info("K-Line manager successfully added K-Line #{cidr_string}: #{reason}")

      {:error, changeset} ->
        Logger.warning("K-Line manager failed to add K-Line #{inspect(changeset)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:pop, cidr_string}, state) do
    case Sencha.Repo.delete(%Sencha.Repo.KLine{cidr: cidr_string}) do
      {:ok, _} ->
        cidr_parsed = cidr_string |> InetCidr.parse_cidr!()
        :ets.take(Sencha.KLine.ETS, cidr_parsed)
        Logger.info("K-Line manager successfully removed K-Line #{cidr_string}")

      {:error, changeset} ->
        Logger.warning("K-Line manager failed to remove K-Line #{inspect(changeset)}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:klined?, ip_address}, _from, state) do
    {:reply,
     {:ok,
      :ets.foldl(
        fn {cidr, reason}, acc ->
          if InetCidr.contains?(cidr, ip_address) and is_nil(acc) do
            reason
          else
            acc
          end
        end,
        nil,
        Sencha.KLine.ETS
      )}, state}
  end
end
