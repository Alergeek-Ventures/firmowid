defmodule Checks.EnforceDesignSystemMarkup do
  @moduledoc """
  Enforces app-level markup rules for buttons and links.

  Outside the landing page and design-system internals, this check bans:

  - raw `<button>` elements
  - raw `<a>` elements
  - `<.link>` when the file is not wired to the design-system link component
  - `use FirmowidWeb.DesignSystem.Imports, ...`
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Use design-system button/link primitives in app code.

      Outside landing pages and design-system internals, raw `<button>` and `<a>` are
      forbidden. `<.link>` must resolve through the design-system link component, and
      `FirmowidWeb.DesignSystem.Imports` is forbidden.
      """,
      params: []
    ]

  alias Credo.IssueMeta

  @forbidden_raw_markup [
    {~r/<button\b/ms, "Use the design-system button component instead of raw `<button>`."},
    {~r/<a\b/ms, "Use the design-system link component instead of raw `<a>`."}
  ]

  @forbidden_import ~r/use\s+FirmowidWeb\.DesignSystem\.Imports\s*,/m
  @link_tag ~r/<\.link\b/ms

  @ds_link_patterns [
    ~r/use\s+FirmowidWeb\s*,\s*:ds_links\b/,
    ~r/use\s+FirmowidWeb\s*,\s*:ds_controls\b/,
    ~r/import\s+FirmowidWeb\.DesignSystem\.Components\.Link\b/,
    ~r/use\s+FirmowidWeb\.DesignSystem\.Imports\s*,\s*:(?:links|controls)\b/
  ]

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if excluded_path?(source_file.filename) do
      []
    else
      source_file
      |> scan_source_file(issue_meta)
      |> Kernel.++(scan_forbidden_import(source_file, issue_meta))
    end
  end

  defp excluded_path?(filename) do
    String.contains?(filename, "lib/firmowid_web/landing/") or
      String.contains?(filename, "lib/firmowid_web/design_system/")
  end

  defp scan_forbidden_import(%SourceFile{filename: filename} = source_file, issue_meta) do
    if String.ends_with?(filename, ".ex") and SourceFile.source(source_file) =~ @forbidden_import do
      [
        format_issue(
          issue_meta,
          message: "Use `FirmowidWeb, :ds_controls` or `:ds_links` instead of `FirmowidWeb.DesignSystem.Imports`.",
          line_no: 1,
          trigger: "FirmowidWeb.DesignSystem.Imports"
        )
      ]
    else
      []
    end
  end

  defp scan_source_file(%SourceFile{filename: filename} = source_file, issue_meta) do
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, filename, source_file))
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, [content]}, _]} = ast, issues, issue_meta, filename, source_file)
       when is_binary(content) do
    line = meta[:line] || 1
    {ast, issues ++ scan_markup(content, issue_meta, line, ds_link_enabled?(filename, source_file))}
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, parts}, _]} = ast, issues, issue_meta, filename, source_file)
       when is_list(parts) do
    line = meta[:line] || 1

    content =
      parts
      |> Enum.map(fn
        part when is_binary(part) -> part
        _ -> " "
      end)
      |> IO.iodata_to_binary()

    {ast, issues ++ scan_markup(content, issue_meta, line, ds_link_enabled?(filename, source_file))}
  end

  defp traverse(ast, issues, _issue_meta, _filename, _source_file), do: {ast, issues}

  defp ds_link_enabled?(_filename, source_file) do
    source =
      SourceFile.source(source_file)

    Enum.any?(@ds_link_patterns, &Regex.match?(&1, source))
  end

  defp scan_markup(content, issue_meta, base_line, ds_link_enabled?) do
    raw_issues =
      Enum.flat_map(@forbidden_raw_markup, fn {regex, message} ->
        regex
        |> Regex.scan(content, return: :index)
        |> Enum.map(fn [{start, len}] ->
          line_no = base_line + count_newlines_before(content, start)
          trigger = binary_part(content, start, len)

          format_issue(issue_meta, message: message, line_no: line_no, trigger: trigger)
        end)
      end)

    link_issues =
      if ds_link_enabled? do
        []
      else
        @link_tag
        |> Regex.scan(content, return: :index)
        |> Enum.map(fn [{start, len}] ->
          line_no = base_line + count_newlines_before(content, start)
          trigger = binary_part(content, start, len)

          format_issue(
            issue_meta,
            message: "`<.link>` requires the design-system link component to be imported via `:ds_links` or `:ds_controls`.",
            line_no: line_no,
            trigger: trigger
          )
        end)
      end

    raw_issues ++ link_issues
  end

  defp count_newlines_before(content, byte_offset) do
    content
    |> binary_part(0, byte_offset)
    |> String.graphemes()
    |> Enum.count(&(&1 == "\n"))
  end
end
