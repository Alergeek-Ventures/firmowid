defmodule Mix.Tasks.Design.Tokens do
  @shortdoc "Generates Tailwind theme tokens from DESIGN.md"
  @moduledoc """
  Generates `assets/css/design-tokens.css` from the YAML frontmatter of `DESIGN.md`.

  `DESIGN.md` is the source of truth for colours (`colors`), the text size scale
  (`typography`, only `fontSize` is emitted) and radii (`rounded`). The block is `@theme static`
  so every token exists as a CSS variable even before a utility uses it. Fonts, spacing and
  animations stay hand-written in `assets/css/theme.css`.

  ## Usage

      mix design.tokens          # Regenerate the CSS file
      mix design.tokens --check  # Fail when the CSS file is out of date
  """

  use Mix.Task

  @design_path "DESIGN.md"
  @output_path "assets/css/design-tokens.css"

  @impl Mix.Task
  @doc "Writes the generated tokens, or with `--check` verifies they are up to date."
  @spec run([String.t()]) :: :ok
  def run(args) do
    {options, []} = OptionParser.parse!(args, strict: [check: :boolean])
    css = @design_path |> File.read!() |> frontmatter() |> render()

    cond do
      not Keyword.get(options, :check, false) ->
        File.write!(@output_path, css)
        Mix.shell().info("Generated #{@output_path} from #{@design_path}")

      File.read(@output_path) == {:ok, css} ->
        :ok

      true ->
        Mix.raise("#{@output_path} is out of date with #{@design_path}. Run `mix design.tokens`.")
    end
  end

  # Keyword-style parsing keeps the order of DESIGN.md (yaml_elixir collects it reversed).
  defp frontmatter(content) do
    ["", yaml, _body] = String.split(content, "---\n", parts: 3)
    YamlElixir.read_from_string!(yaml, maps_as_keywords: true)
  end

  defp render(tokens) do
    declarations =
      ["--color-*: initial;", "--text-*: initial;"] ++
        declarations(tokens, "colors", "color", & &1) ++
        declarations(tokens, "typography", "text", &field!(&1, "fontSize")) ++
        declarations(tokens, "rounded", "radius", & &1)

    """
    /* Generated from DESIGN.md by `mix design.tokens`. Do not edit by hand. */
    @theme static {
    #{Enum.map_join(declarations, "\n", &"  #{&1}")}
    }
    """
  end

  defp declarations(tokens, section, namespace, value) do
    for {name, token} <- tokens |> field!(section) |> Enum.reverse() do
      "--#{namespace}-#{name}: #{value.(token)};"
    end
  end

  defp field!(pairs, key) do
    {^key, value} = List.keyfind(pairs, key, 0)
    value
  end
end
