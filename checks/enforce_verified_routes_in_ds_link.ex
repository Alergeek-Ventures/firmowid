defmodule Checks.EnforceVerifiedRoutesInDsLink do
  @moduledoc """
  Enforces verified route sigils for literal internal paths passed to the design-system `link/1` component.

  This check only applies in files that use `FirmowidWeb.DesignSystem.Components.Link`.
  It flags raw string literals passed to `navigate`, `patch`, and `redirect` on `<.link ...>`.

  ## Bad

      <.link navigate="/zaproszenia">Dodaj pracownika</.link>
      <.link redirect={"/auth/user/google"}>Google</.link>

  ## Good

      <.link navigate={~p"/zaproszenia"}>Dodaj pracownika</.link>
      <.link patch={~p"/zarzadzanie/projekty"}>Projekty</.link>
      <.link patch={path}>Projekty</.link>
  """

  use Credo.Check,
    base_priority: :normal,
    category: :consistency,
    explanations: [
      check: """
      Use `~p` verified routes for literal internal paths passed to the design-system
      `link/1` component.

      This check flags raw string literals in `navigate=`, `patch=`, and `redirect=`
      attributes on `<.link ...>` when the file uses
      `FirmowidWeb.DesignSystem.Components.Link`.
      """,
      params: []
    ]

  alias Credo.IssueMeta

  @import_regex ~r/import\s+FirmowidWeb\.DesignSystem\.Components\.Link\b/

  @bad_attr_regex ~r/
    <\.link\b
    (?:(?!<\/\.link>|\/?>).)*?
    \b(?<attr>navigate|patch|redirect)\s*=\s*
    (?:
      "(?<literal>[^"]*)"
      |
      \{\s*"(?<braced>[^"]*)"\s*\}
    )
  /msx

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if uses_ds_link?(source_file) do
      scan_source_file(source_file, issue_meta)
    else
      []
    end
  end

  defp uses_ds_link?(%SourceFile{filename: filename} = source_file) do
    cond do
      String.ends_with?(filename, ".ex") ->
        SourceFile.source(source_file) =~ @import_regex

      String.ends_with?(filename, ".html.heex") ->
        filename
        |> companion_ex_file()
        |> File.exists?()
        |> case do
          true -> File.read!(companion_ex_file(filename)) =~ @import_regex
          false -> false
        end

      true ->
        false
    end
  end

  defp companion_ex_file(filename) do
    String.replace_suffix(filename, ".html.heex", ".ex")
  end

  defp scan_source_file(%SourceFile{filename: filename} = source_file, issue_meta) do
    source = SourceFile.source(source_file)

    if String.ends_with?(filename, ".html.heex") do
      find_issues(source, issue_meta, 1)
    else
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, [content]}, _opts]} = ast, issues, issue_meta) when is_binary(content) do
    base_line = meta[:line] || 1
    {ast, issues ++ find_issues(content, issue_meta, base_line)}
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, parts}, _opts]} = ast, issues, issue_meta) when is_list(parts) do
    base_line = meta[:line] || 1

    content =
      parts
      |> Enum.map(fn
        part when is_binary(part) -> part
        _ -> " "
      end)
      |> IO.iodata_to_binary()

    {ast, issues ++ find_issues(content, issue_meta, base_line)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp find_issues(content, issue_meta, base_line) do
    @bad_attr_regex
    |> Regex.scan(content, return: :index, capture: :all_names)
    |> Enum.map(fn [attr: {attr_start, attr_len}] ->
      attr = binary_part(content, attr_start, attr_len)
      line_no = base_line + count_newlines_before(content, attr_start)
      issue_for(attr, line_no, issue_meta)
    end)
  end

  defp count_newlines_before(content, byte_offset) do
    content
    |> binary_part(0, byte_offset)
    |> String.graphemes()
    |> Enum.count(&(&1 == "\n"))
  end

  defp issue_for(attr, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message: "Use `~p` for literal `#{attr}` paths in design-system `<.link>`.",
      line_no: line_no,
      trigger: attr
    )
  end
end
