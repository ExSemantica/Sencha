# Main stuff
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
defmodule Sencha do
  @moduledoc """
  Documentation for `Sencha`.
  """

  @re_hostname ~r/^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/

  @doc """
  Hello world.

  ## Examples

      iex> Sencha.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Checks if the input is a valid hostname.

  ## Examples

      iex> Sencha.check_hostname("what@example.com")
      false

      iex> Sencha.check_hostname("example.com")
      true

  """
  def check_hostname(hostname) do
    # SEE: RFC 1123
    Regex.match?(@re_hostname, hostname)
  end
end
