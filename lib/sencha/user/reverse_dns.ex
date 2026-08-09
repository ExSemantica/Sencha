# Reverse DNS lookup
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
defmodule Sencha.User.ReverseDNS do
  @moduledoc """
  Reverse DNS lookup
  """
  @doc """
  Performs the reverse DNS lookup.

  Ensure you do this in a `Task` of sorts.
  """
  def lookup(addr) do
    Process.sleep(5000)

    {:lookup, addr,
     case :inet_res.gethostbyaddr(addr) do
       {:ok, hostent} ->
         {:hostent, h_name, _, _, _, _} = hostent
         host = h_name |> to_string()

         if byte_size(host) > Sencha.Constrain.User.max_length_host() do
           {:error, :too_long}
         else
           {:ok, h_name |> to_string}
         end

       {:error, reason} ->
         {:error, reason}
     end}
  end
end
