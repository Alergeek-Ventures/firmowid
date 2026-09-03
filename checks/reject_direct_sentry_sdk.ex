defmodule Checks.RejectDirectSentrySdk do
  @moduledoc """
  Disallows direct references to the Sentry SDK.

  Application code should alias or use `Firmowid.Sentry` instead of referring to
  `Sentry` or `Elixir.Sentry` directly.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Credo.IssueMeta

  @impl true
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> scan_root(issue_meta)
  end

  defp scan_root({:__block__, _, expressions}, issue_meta) do
    scan_expressions(expressions, issue_meta)
  end

  defp scan_root({:defmodule, _, [_, options]}, issue_meta) do
    options
    |> Keyword.get(:do)
    |> scan_module_body(issue_meta)
  end

  defp scan_root(expression, issue_meta), do: scan_expression(expression, issue_meta, false)

  defp scan_module_body({:__block__, _, expressions}, issue_meta) do
    scan_expressions(expressions, issue_meta)
  end

  defp scan_module_body(expression, issue_meta), do: scan_expression(expression, issue_meta, false)

  defp scan_expressions(expressions, issue_meta) do
    {issues, _boundary?} =
      Enum.reduce(expressions, {[], false}, fn expression, {issues, boundary?} ->
        expression_issues = scan_expression(expression, issue_meta, boundary?)
        boundary? = boundary? or module_boundary_alias?(expression)
        {issues ++ expression_issues, boundary?}
      end)

    issues
  end

  defp scan_expression({:defmodule, _, [_, options]}, issue_meta, _boundary?) do
    options
    |> Keyword.get(:do)
    |> scan_module_body(issue_meta)
  end

  defp scan_expression(expression, issue_meta, boundary?) do
    Credo.Code.prewalk(
      expression,
      &traverse(
        &1,
        &2,
        issue_meta,
        boundary?,
        module_boundary_alias?(expression),
        grouped_elixir_sentry_alias?(expression) or grouped_firmowid_sentry_alias?(expression)
      )
    )
  end

  defp traverse({:alias, meta, [_grouped]} = ast, issues, issue_meta, _boundary?, _skip_boundary_alias?, true) do
    if grouped_elixir_sentry_alias?(ast) do
      {ast, issues ++ [issue_for([:"Elixir", :Sentry], meta[:line], issue_meta)]}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {:__aliases__, meta, parts} = ast,
         issues,
         issue_meta,
         boundary?,
         skip_boundary_alias?,
         skip_grouped_sentry?
       ) do
    if direct_sentry_alias?(parts, boundary?) and
         not (skip_boundary_alias? and parts == [:Sentry]) and
         not (skip_grouped_sentry? and sentry_alias_parts?(parts)) do
      {ast, issues ++ [issue_for(parts, meta[:line], issue_meta)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _boundary?, _skip_boundary_alias?, _skip_grouped_sentry?), do: {ast, issues}

  defp module_boundary_alias?({:alias, _, [{:__aliases__, _, [:Firmowid, :Sentry]} | options]}) do
    options
    |> alias_options()
    |> Keyword.get(:as, :default)
    |> local_sentry_alias?()
  end

  defp module_boundary_alias?({:alias, _, [grouped]}) do
    grouped_alias?(grouped, :Firmowid) and grouped_contains_exact_sentry?(grouped)
  end

  defp module_boundary_alias?(_), do: false

  defp grouped_elixir_sentry_alias?({:alias, _, [grouped]}) do
    grouped_alias?(grouped, :"Elixir") and grouped_contains_sentry?(grouped)
  end

  defp grouped_elixir_sentry_alias?(_), do: false

  defp grouped_firmowid_sentry_alias?({:alias, _, [grouped]}) do
    grouped_alias?(grouped, :Firmowid) and grouped_contains_sentry?(grouped)
  end

  defp grouped_firmowid_sentry_alias?(_), do: false

  defp grouped_alias?({{:., _, [{:__aliases__, _, [:Firmowid]}, :{}]}, _, _children}, :Firmowid), do: true

  defp grouped_alias?({{:., _, [{:__aliases__, _, [:"Elixir"]}, :{}]}, _, _children}, :"Elixir"), do: true

  defp grouped_alias?(_, _root), do: false

  defp grouped_contains_exact_sentry?(grouped),
    do: grouped |> grouped_children() |> Enum.any?(&match?({:__aliases__, _, [:Sentry]}, &1))

  defp grouped_contains_sentry?(grouped),
    do: grouped |> grouped_children() |> Enum.any?(&match?({:__aliases__, _, [:Sentry | _]}, &1))

  defp grouped_children({{:., _, _}, _, children}), do: children
  defp grouped_children(_), do: []

  defp sentry_alias_parts?([:Sentry | _]), do: true
  defp sentry_alias_parts?(_), do: false

  defp alias_options([options]) when is_list(options), do: options
  defp alias_options(_), do: []

  defp local_sentry_alias?(:default), do: true
  defp local_sentry_alias?({:__aliases__, _, [:Sentry]}), do: true
  defp local_sentry_alias?(_), do: false

  defp direct_sentry_alias?([:"Elixir", :Sentry | _], _firmowid_sentry_alias?), do: true
  defp direct_sentry_alias?([:Sentry | _], true), do: false
  defp direct_sentry_alias?([:Sentry | _], false), do: true
  defp direct_sentry_alias?(_, _firmowid_sentry_alias?), do: false

  defp issue_for(parts, line_no, issue_meta) do
    module = Enum.map_join(parts, ".", &to_string/1)

    format_issue(
      issue_meta,
      message: "Do not reference `#{module}` directly. Alias or use `Firmowid.Sentry` instead.",
      line_no: line_no,
      trigger: module
    )
  end
end
