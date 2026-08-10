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
defmodule Sencha.User.Numeric.ERR_NOSUCHCHANNEL do
  @moduledoc false
  @behaviour Sencha.User.Numeric
  @impl Sencha.User.Numeric
  def handle_encode(target, %{channel: channel}) do
    %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :hostname),
      command: "403",
      middle: [
        target[:nickname] || "*",
        channel
      ],
      trailing: "No such channel"
    }
  end
end
