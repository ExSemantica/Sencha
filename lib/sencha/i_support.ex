# RPL_ISUPPORT features enumeration
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
defmodule Sencha.ISupport do
  @moduledoc """
  RPL_ISUPPORT features enumeration

  TODO: IRCv3 lets you change supported parameters.
  """
  def get() do
    [
      "AWAYLEN=#{Sencha.Constrain.User.max_length_away()}",
      "CASEMAPPING=ascii",
      # TODO: CHANLIMIT
      "CHANMODES=#{?a..?d |> Enum.map(&(Sencha.Channel.modes(&1) |> MapSet.to_list())) |> Enum.intersperse(",") |> to_string}",
      "CHANNELLEN=#{Sencha.Constrain.Channel.max_length_name()}",
      "CHANTYPES=#{Sencha.Constrain.Channel.supported_prefixes() |> to_string()}",
      "CLIENTTAGDENY=*,-typing",
      # TODO: ELIST
      "EXCEPTS=e",
      # TODO: EXTBAN
      "HOSTLEN=#{Sencha.Constrain.User.max_length_host()}",
      # TODO: INVEX
      "KICKLEN=#{Sencha.Constrain.Channel.max_length_kick()}",
      # TODO: MAXLIST, MAXTARGETS
      "MODES=#{Sencha.Constrain.Channel.max_variable_modes()}",
      "NETWORK=#{Application.get_env(:sencha, :network_name, "Sencha")}",
      "NICKLEN=#{Sencha.Constrain.User.max_length_name()}",
      "PREFIX=(ov)@+",
      # TODO: SAFELIST, SILENCE, STATUSMSG, TARGMAX
      "TOPICLEN=#{Sencha.Constrain.Channel.max_length_topic()}",
      "USERLEN=#{Sencha.Constrain.User.max_length_ident()}"
    ]
  end
end
