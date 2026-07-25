# Parse IRC glob masks
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
defmodule Sencha.Mask do
  @moduledoc """
  Parse IRC glob masks
  """
  import NimbleParsec

  # Match special wildcard characters
  any_string = string("*") |> replace(:any_string)
  any_char = string("?") |> replace(:any_char)

  # Only match UTF-8 characters that are NOT '*' (42) or '?' (63)
  literal_char = utf8_char(not: ?*, not: ??)

  # Combine literals into a single string token
  literal =
    times(literal_char, min: 1)
    |> reduce({List, :to_string, []})
    |> tag(:literal)

  # Core grammar loop
  glob_pattern =
    repeat(choice([any_string, any_char, literal]))
    |> eos()

  # Define the parser function
  defparsecp(:parse, glob_pattern)

  def valid?(match_mask) do
    case parse(match_mask) do
      {:ok, _, "", _, _, _} -> true
      _ -> false
    end
  end

  def match?(string, match_mask) do
    {:ok, ast, "", _, _, _} = parse(match_mask)

    {:ok, regex} =
      [
        "^",
        ast
        |> Enum.reduce([], fn item, acc ->
          [
            case item do
              {:literal, [literal]} -> Regex.escape(literal)
              :any_string -> ".*"
              :any_char -> "."
            end
            | acc
          ]
        end)
        |> Enum.reverse(),
        "$"
      ]
      |> Enum.join()
      |> Regex.compile()

    Regex.match?(regex, string)
  end
end
