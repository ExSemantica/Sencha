# RFC 2812 IRC prefix data structure
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
defmodule Sencha.Prefix do
  @moduledoc """
  RFC 2812 IRC prefix data structure

  Note there are two cases:
  - There is only a host
  - There is a nickname, user, and host
  """
  @enforce_keys [:host]
  @re_validate ~r/^([^\!\?\@]+)\!([^\!\?\@]+)\@([^\!\?\@]+)$/
  defstruct [:nickname, :user, :host]

  @doc """
  Parse a prefix, note that not all of the generated prefixes are valid, so you
  should check validity of the nickname/user/host in another place.
  """
  def decode(what) do
    case Regex.run(@re_validate, what) do
      [_what, nickname, user, host] ->
        %__MODULE__{nickname: nickname, user: user, host: host}

      _error ->
        %__MODULE__{nickname: nil, user: nil, host: what}
    end
  end

  def encode(%__MODULE__{nickname: nil, user: nil, host: host}) do
    host
  end

  def encode(%__MODULE__{nickname: nickname, user: user, host: host}) do
    nickname <> "!" <> user <> "@" <> host
  end
end
