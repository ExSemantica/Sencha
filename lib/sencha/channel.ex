# Channel state
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
defmodule Sencha.Channel do
  @moduledoc """
  Channel state
  """
  @doc """
  All channel mode characters that can be set by a channel operator
  """
  def modes_noparam(), do: MapSet.new(~c(s))

  @doc """
  All channel mode characters that are parametered and settable by a channel operator
  """
  def modes_param(), do: MapSet.new(~c(b))

  @doc """
  All channel mode characters supported

  Not all can be set by a channel operator
  """
  def modes_noparam_all(), do: MapSet.new(~c()) |> MapSet.union(modes_noparam())

  @doc """
  All channel mode characters that are parametered and supported

  Not all can be set by a channel operator
  """
  def modes_param_all(), do: MapSet.new(~c()) |> MapSet.union(modes_param())
end
