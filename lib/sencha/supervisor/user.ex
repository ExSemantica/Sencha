# DynamicSupervisor for `Sencha.User`
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
defmodule Sencha.Supervisor.User do
  @moduledoc """
  DynamicSupervisor for `Sencha.User`
  """
  require Logger
  use DynamicSupervisor

  # ===========================================================================
  # Public API
  # ===========================================================================
  @doc """
  Starts this supervisor
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Tries to start an unregistered `Sencha.User` with given arguments

  Also handles the maximum user count
  """
  def start_user(args) do
    current_children = DynamicSupervisor.count_children(__MODULE__)
    historic_children = :persistent_term.get(__MODULE__.Maximum, 0)
    anticipated_children = max(historic_children, current_children.active + 1)

    if anticipated_children > historic_children do
      # TODO: This is an expensive operation, maybe optimize this?
      :persistent_term.put(__MODULE__.Maximum, anticipated_children)
    end

    DynamicSupervisor.start_child(__MODULE__, {Sencha.User, args})
  end

  @doc """
  Counts users on this node

  NOTE: `:persistent_term` is local
  """
  def count() do
    children = DynamicSupervisor.count_children(__MODULE__)

    %{active: children.active, maximum: :persistent_term.get(__MODULE__.Maximum, 0)}
  end

  @doc """
  Gathers children, returning their PIDs
  """
  def gather() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, child, _type, _modules} -> child end)
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================
  @impl DynamicSupervisor
  def init(_init_arg) do
    Logger.info("User state supervisor started")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
