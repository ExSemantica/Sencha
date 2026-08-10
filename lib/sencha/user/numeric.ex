# Skeletons for numeric responses
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
defmodule Sencha.User.Numeric do
  @moduledoc """
  Skeletons for numeric responses
  """
  @callback handle_encode(target :: map, args :: map) :: %Sencha.Message{}
  @doc """
  Make an IRCv3 numeric name into a `Sencha.Message`

  - `type`: the numeric as an atom
  - `target`: a `Sencha.Prefix`
  - `args`: anything else that is needed
  """
  def encode(type, target, args \\ %{}) do
    apply(Module.concat([__MODULE__, type]), :handle_encode, [target, args])
  end
end
