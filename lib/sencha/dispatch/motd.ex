# Dispatch IRCv3 command MOTD
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
defmodule Sencha.Dispatch.Motd do
  @moduledoc false
  def handle(
        state,
        _message
      ) do
    # TODO
    motd = :persistent_term.get(Sencha.MOTD, :nomotd)

    case motd do
      :nomotd ->
        state
        |> Sencha.Dispatch.Numeric.send(:ERR_NOMOTD)

      motd ->
        state |> Sencha.Dispatch.Numeric.send(:RPL_MOTDSTART)

        for line <- motd do
          state |> Sencha.Dispatch.Numeric.send(:RPL_MOTD, %{line: line})
        end

        state |> Sencha.Dispatch.Numeric.send(:RPL_ENDOFMOTD)
    end
  end
end
