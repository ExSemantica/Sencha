# Handle numeric response
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
defmodule Sencha.User.Numeric.RPL_LUSERCLIENT do
  @moduledoc false
  @behaviour Sencha.User.Numeric
  @impl Sencha.User.Numeric
  def handle_encode(target, _args) do
    connections_num =
      length(
        :global.registered_names()
        |> Enum.filter(fn {type, _pid} -> type == Sencha.User end)
      )

    nodes_num = length([node() | Node.list()])

    %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :hostname),
      command: "251",
      middle: [
        target[:nickname] || "*"
      ],
      # TODO: invisibility
      trailing: "There are #{connections_num} users and 0 invisible on #{nodes_num} servers"
    }
  end
end
