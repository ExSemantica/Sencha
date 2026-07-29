# RFC 2812 IRC prefix
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
  RFC 2812 IRC prefix

  Note there are two cases:
  - There is only a host
  - There is a nickname, user, and host
  """
  @re_validate ~r/^(?:([^\!\@]+)\!)?(?:([^\!\@]+)\@)?([^\!\@]+)$/

  @doc """
  Parse a prefix, note that not all of the generated prefixes are valid, so you
  should check validity of the nickname/user/host in another place.
  """
  def decode(what) do
    case Regex.run(@re_validate, what) do
      [_what, nickname, user, host] ->
        %{nickname: nickname, user: user, host: host}

      _error ->
        %{nickname: nil, user: nil, host: what}
    end
  end

  @doc """
  Makes this prefix into a string
  """
  def encode(%{nickname: nil, user: nil, host: host}) do
    host
  end

  def encode(%{nickname: nickname, user: user, host: host}) do
    nickname <> "!" <> user <> "@" <> host
  end

  @doc """
  Checks if this prefix matches a given match mask
  """
  def match?(%{nickname: nickname, user: user, host: host}, match) do
    [_, m_nickname, m_user, m_host] = Regex.run(@re_validate, match)

    nickname? =
      if is_nil(nickname) do
        true
      else
        m_nickname = if m_nickname == "", do: "*", else: m_nickname

        Sencha.Mask.match?(nickname, m_nickname)
      end

    user? =
      if is_nil(user) do
        true
      else
        m_user = if m_user == "", do: "*", else: m_user

        Sencha.Mask.match?(user, m_user)
      end

    host? = Sencha.Mask.match?(host, m_host)

    [nickname?, user?, host?] |> Enum.all?()
  end
end
