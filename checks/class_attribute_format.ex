defmodule Checks.ClassAttributeFormat do
  @moduledoc """
  Enforces a canonical format for `class=` attributes in HEEx templates.

  ## Allowed patterns

  1. **Plain string** — `class="flex items-center"`
  2. **Array** — `class={["base", @active && "bg-blue", @class]}`
     - Max one string literal, must be first element
     - Element order: string → `*_styles()` calls → conditionals → variables
     - Conditionals: `&&`, `if`, `case`, `cond`
     - Variables: `@var`, `@rest[:key]`
  3. **Variable pass-through** — `class={@class}` or `class={@rest[:class]}`
  4. **Styles function** — `class={button_styles(assigns)}` (any `*_styles()`)

  ## What this check flags

  - `classes()` wrapper usage (redundant, HEEx arrays work identically)
  - Multiple string literals in an array (merge into one)
  - String interpolation in class attributes (use array instead)
  - Bare conditionals not wrapped in array
  - Wrong element ordering in arrays
  - Non-`_styles` function calls as class values
  - Piped arrays (`[...] |> Enum.join(...)`)
  """

  use Credo.Check,
    base_priority: :normal,
    category: :consistency,
    explanations: [
      check: """
      Enforces canonical `class=` attribute format in HEEx templates.

      Allowed patterns:
      - `class="static classes"` — plain string
      - `class={["base", @cond && "extra", @class]}` — ordered array
      - `class={@class}` — variable pass-through
      - `class={button_styles(assigns)}` — styles function

      Arrays must have at most one string (first), then styles calls,
      then conditionals, then variables.
      """,
      params: []
    ]

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    filename = source_file.filename

    if String.ends_with?(filename, ".heex") do
      source = SourceFile.source(source_file)
      find_class_violations(source, issue_meta, _base_line = 1)
    else
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  # ── AST traversal for ~H sigils ────────────────────────────────────────

  defp traverse({:sigil_H, meta, [{:<<>>, _, [content]}, _opts]} = ast, issues, issue_meta) when is_binary(content) do
    base_line = meta[:line] || 1
    new_issues = find_class_violations(content, issue_meta, base_line)
    {ast, issues ++ new_issues}
  end

  defp traverse({:sigil_H, meta, [{:<<>>, _, content_parts}, _opts]} = ast, issues, issue_meta)
       when is_list(content_parts) do
    base_line = meta[:line] || 1
    content = extract_heex_content(content_parts)
    new_issues = find_class_violations(content, issue_meta, base_line)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp extract_heex_content(parts) do
    parts
    |> Enum.map(fn
      part when is_binary(part) -> part
      _ -> " "
    end)
    |> IO.iodata_to_binary()
  end

  # ── Expression extraction via balanced brace matching ──────────────────

  @class_expr_start ~r/class=\{/

  defp find_class_violations(content, issue_meta, base_line) do
    @class_expr_start
    |> Regex.scan(content, return: :index)
    |> Enum.flat_map(fn [{match_start, match_len}] ->
      expr_start = match_start + match_len
      line_no = base_line + count_newlines_before(content, match_start)

      case extract_balanced_expr(content, expr_start) do
        {:ok, expr_string} ->
          validate_class_expr(expr_string, issue_meta, line_no)

        :error ->
          []
      end
    end)
  end

  defp extract_balanced_expr(content, start) do
    # Regex returns byte offsets, so use binary_part for slicing
    remaining = binary_part(content, start, byte_size(content) - start)
    chars = String.to_charlist(remaining)
    scan_braces(chars, _depth = 0, _in_string = false, _acc = [])
  end

  defp scan_braces([], _depth, _in_string, _acc), do: :error

  # Escaped character inside string
  defp scan_braces([?\\, c | rest], depth, true, acc) do
    scan_braces(rest, depth, true, [c, ?\\ | acc])
  end

  # Toggle string mode
  defp scan_braces([?" | rest], depth, in_string, acc) do
    scan_braces(rest, depth, !in_string, [?" | acc])
  end

  # Opening brace (not in string)
  defp scan_braces([?{ | rest], depth, false, acc) do
    scan_braces(rest, depth + 1, false, [?{ | acc])
  end

  # Closing brace at depth 0 — we found the match
  defp scan_braces([?} | _rest], 0, false, acc) do
    {:ok, acc |> Enum.reverse() |> List.to_string()}
  end

  # Closing brace at depth > 0
  defp scan_braces([?} | rest], depth, false, acc) do
    scan_braces(rest, depth - 1, false, [?} | acc])
  end

  # Any other character
  defp scan_braces([c | rest], depth, in_string, acc) do
    scan_braces(rest, depth, in_string, [c | acc])
  end

  # ── Validation entry point ─────────────────────────────────────────────

  defp validate_class_expr(expr_string, issue_meta, line_no) do
    case Code.string_to_quoted(expr_string) do
      {:ok, ast} -> check_expr(ast, issue_meta, line_no)
      {:error, _} -> []
    end
  end

  # ── Top-level expression classification ────────────────────────────────

  # Pattern 2: Array — validate elements
  defp check_expr(list, issue_meta, line_no) when is_list(list) do
    validate_array_elements(list, issue_meta, line_no)
  end

  # Pattern 3: Variable pass-through @var
  defp check_expr({:@, _, [{_name, _, nil}]}, _issue_meta, _line_no), do: []

  # Pattern 3: @rest[:key]
  defp check_expr({{:., _, [Access, :get]}, _, [{:@, _, _}, _key]}, _issue_meta, _line_no), do: []

  # V1: classes() wrapper
  defp check_expr({:classes, _, _}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Remove classes() wrapper, use plain array")]
  end

  # V9: [...] |> Enum.join(...)
  defp check_expr({:|>, _, [_left, {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, _}]}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Remove Enum.join pipe, use plain array")]
  end

  # V3: String interpolation "...#{...}..."
  defp check_expr({:<<>>, _, parts}, issue_meta, line_no) when is_list(parts) and length(parts) > 1 do
    [issue(issue_meta, line_no, "Use array notation instead of string interpolation")]
  end

  # Pattern 4: *_styles() function call
  defp check_expr({func_name, _, args}, issue_meta, line_no)
       when is_atom(func_name) and is_list(args) and func_name not in [:if, :case, :cond, :&&] do
    if styles_function?(func_name) do
      []
    else
      [issue(issue_meta, line_no, "Only *_styles() functions allowed, found #{func_name}()")]
    end
  end

  # V4: Bare && conditional
  defp check_expr({:&&, _, _}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Wrap conditional in array")]
  end

  # V5: Bare if/case/cond
  defp check_expr({:if, _, _}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Wrap if expression in array")]
  end

  defp check_expr({:case, _, _}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Wrap case expression in array")]
  end

  defp check_expr({:cond, _, _}, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Wrap cond expression in array")]
  end

  # Anything else
  defp check_expr(_ast, issue_meta, line_no) do
    [issue(issue_meta, line_no, "Unrecognized class expression format")]
  end

  # ── Array element validation ───────────────────────────────────────────

  defp validate_array_elements(elements, issue_meta, line_no) do
    classified = Enum.map(elements, &{classify_element(&1), &1})

    check_string_count(classified, issue_meta, line_no) ++
      check_element_order(classified, issue_meta, line_no) ++
      check_unknown_elements(classified, issue_meta, line_no)
  end

  # V2/V7: Multiple strings in array
  defp check_string_count(classified, issue_meta, line_no) do
    string_count = Enum.count(classified, fn {{type, _}, _} -> type == :string end)

    cond do
      string_count > 1 ->
        [issue(issue_meta, line_no, "Merge multiple strings into one base string (found #{string_count})")]

      string_count == 1 ->
        case classified do
          [{{:string, _}, _} | _] -> []
          _ -> [issue(issue_meta, line_no, "String literal must be the first element in the array")]
        end

      true ->
        []
    end
  end

  # V6: Wrong ordering — priorities must be non-decreasing
  defp check_element_order(classified, issue_meta, line_no) do
    priorities = Enum.map(classified, fn {{_type, priority}, _} -> priority end)

    if non_decreasing?(priorities) do
      []
    else
      [issue(issue_meta, line_no, "Wrong element order: use string → styles → conditionals → variables")]
    end
  end

  defp non_decreasing?([]), do: true
  defp non_decreasing?([_]), do: true
  defp non_decreasing?([a, b | rest]), do: a <= b and non_decreasing?([b | rest])

  defp check_unknown_elements(classified, issue_meta, line_no) do
    Enum.flat_map(classified, fn
      {{:unknown, _}, _} ->
        [issue(issue_meta, line_no, "Unrecognized element in class array")]

      _ ->
        []
    end)
  end

  # ── Element classification ─────────────────────────────────────────────
  #
  # Returns {type, priority}:
  #   :string         → 0
  #   :styles_call    → 1
  #   :conditional    → 2
  #   :variable       → 3
  #   :unknown        → 99

  defp classify_element(str) when is_binary(str), do: {:string, 0}

  # Variable: @var (must come before general function clause since :@ is an atom)
  defp classify_element({:@, _, [{_name, _, nil}]}), do: {:variable, 3}

  # Variable: @rest[:key]
  defp classify_element({{:., _, [Access, :get]}, _, [{:@, _, _}, _key]}), do: {:variable, 3}

  # && expression (must come before general function clause since :&& is an atom)
  defp classify_element({:&&, _, [_lhs, rhs]}) do
    if styles_rhs?(rhs), do: {:styles_call, 1}, else: {:conditional, 2}
  end

  # String interpolation (must come before general function clause since :<<>> is an atom)
  defp classify_element({:<<>>, _, parts}) when is_list(parts) and length(parts) > 1 do
    {:unknown, 99}
  end

  # *_styles() / if / case / cond / unknown function call
  defp classify_element({func_name, _, args}) when is_atom(func_name) and is_list(args) do
    cond do
      styles_function?(func_name) -> {:styles_call, 1}
      func_name in [:if, :case, :cond] -> {:conditional, 2}
      true -> {:unknown, 99}
    end
  end

  defp classify_element(_), do: {:unknown, 99}

  defp styles_rhs?({func_name, _, args}) when is_atom(func_name) and is_list(args) do
    styles_function?(func_name)
  end

  defp styles_rhs?(_), do: false

  # ── Helpers ────────────────────────────────────────────────────────────

  defp styles_function?(name) do
    name |> Atom.to_string() |> String.ends_with?("_styles")
  end

  defp count_newlines_before(content, position) do
    content
    |> binary_part(0, position)
    |> String.graphemes()
    |> Enum.count(&(&1 == "\n"))
  end

  defp issue(issue_meta, line_no, message) do
    format_issue(issue_meta, message: message, line_no: line_no)
  end
end
