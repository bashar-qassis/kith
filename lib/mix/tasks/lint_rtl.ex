defmodule Mix.Tasks.Lint.Rtl do
  @moduledoc """
  Lints `.heex` templates for banned directional Tailwind CSS utilities.

  The following utilities are banned because they break RTL layouts:
  `ml-`, `mr-`, `pl-`, `pr-`, `left-`, `right-`

  Use logical property equivalents instead:
  `ms-`, `me-`, `ps-`, `pe-`, `start-`, `end-`

  ## Usage

      mix lint.rtl
  """

  use Mix.Task

  @shortdoc "Checks .heex templates for banned directional Tailwind utilities"

  @impl Mix.Task
  def run(_args) do
    files = Path.wildcard("lib/**/*.heex")
    patterns = banned_patterns()

    violations =
      Enum.flat_map(files, fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_num} ->
          Enum.flat_map(patterns, fn pattern ->
            case Regex.run(pattern, line) do
              [match | _] -> [{file, line_num, match, String.trim(line)}]
              nil -> []
            end
          end)
        end)
      end)

    if violations == [] do
      Mix.shell().info("No banned directional Tailwind utilities found in .heex templates.")
    else
      Mix.shell().error("Found #{length(violations)} banned directional Tailwind utilities:\n")

      Enum.each(violations, fn {file, line, match, context} ->
        Mix.shell().error("  #{file}:#{line} -- found `#{match}`")
        Mix.shell().error("    #{context}\n")
      end)

      Mix.shell().error("""
      Use logical property equivalents for RTL support:
        ml-/mr- -> ms-/me-    (margin-start/end)
        pl-/pr- -> ps-/pe-    (padding-start/end)
        left-/right- -> start-/end-
        border-l-/border-r- -> border-s-/border-e-
        rounded-l-/rounded-r- -> rounded-s-/rounded-e-
      """)

      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp banned_patterns do
    [
      ~r/\b(ml-|mr-)\d/,
      ~r/\b(pl-|pr-)\d/,
      ~r/\b(left-|right-)\d/,
      ~r/\b(border-l-|border-r-)\d/,
      ~r/\b(rounded-l-|rounded-r-|rounded-tl-|rounded-tr-|rounded-bl-|rounded-br-)/,
      ~r/\b(scroll-ml-|scroll-mr-|scroll-pl-|scroll-pr-)\d/
    ]
  end
end
