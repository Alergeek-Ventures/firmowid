defmodule Checks.CheckModulePlacement do
  @moduledoc """
  Enforces that Phoenix modules are placed in their correct folders based on type.

  ## Rules

  1. Files in `*/views/` must contain `use FirmowidWeb, :live_view` (direct `Phoenix.LiveView` is forbidden)
  2. Files in `*/components/` must contain `use FirmowidWeb, :live_component`
     or `use FirmowidWeb, :html` (direct `Phoenix.Component` or `Phoenix.LiveComponent` is forbidden)
  3. Files in `*/controllers/` must contain `use FirmowidWeb, :controller` (direct `Phoenix.Controller` is forbidden)
  4. Files in `*/utilities/` must NOT contain any `use FirmowidWeb, :*` macro or direct Phoenix macros

  ## Exemptions

  - Test files (`*_test.exs`) are exempt from all checks

  ## Rationale

  This enforces the vertical "by feature" organization where folder structure
  communicates module type, eliminating the need for type suffixes in module names.
  All modules must go through the `FirmowidWeb` macro hub to ensure consistent
  imports and helpers.
  """

  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: @moduledoc
    ]

  # Modules that are exempt from folder-type constraints.
  # CoreComponents must use Phoenix.Component directly (can't import itself).
  # JSON renderers are pure render modules with no Phoenix macro needs.
  @exempt_files [
    "design_system/components/core_components.ex",
    "infrastructure/components/error_json.ex",
    "infrastructure/components/changeset_json.ex"
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params \\ []) do
    issue_meta = IssueMeta.for(source_file, [])
    filename = source_file.filename

    cond do
      String.ends_with?(filename, "_test.exs") ->
        []

      Enum.any?(@exempt_files, &String.ends_with?(filename, &1)) ->
        []

      true ->
        check_folder_constraints(source_file, issue_meta, filename)
    end
  end

  defp check_folder_constraints(source_file, issue_meta, filename) do
    cond do
      String.contains?(filename, "/views/") ->
        validate_views_folder(source_file, issue_meta)

      String.contains?(filename, "/components/") ->
        validate_components_folder(source_file, issue_meta)

      String.contains?(filename, "/controllers/") ->
        validate_controllers_folder(source_file, issue_meta)

      String.contains?(filename, "/utilities/") ->
        validate_utilities_folder(source_file, issue_meta)

      true ->
        # Not a folder we care about
        []
    end
  end

  # --- Views folder: must use :live_view, no direct Phoenix.LiveView ---

  defp validate_views_folder(source_file, issue_meta) do
    uses = extract_uses(source_file)

    # Check for forbidden direct Phoenix usage
    phoenix_issues =
      uses
      |> Enum.filter(&match?({:phoenix, :live_view, _}, &1))
      |> Enum.map(fn {:phoenix, :live_view, line_no} ->
        format_issue(
          issue_meta,
          message: """
          Do not use `use Phoenix.LiveView` directly in views/ folder.
          Use `use FirmowidWeb, :live_view` instead to ensure consistent helpers.
          """,
          line_no: line_no,
          trigger: "Phoenix.LiveView"
        )
      end)

    # Check for required FirmowidWeb macro
    has_live_view? = Enum.any?(uses, &match?({:firmowid_web, :live_view, _}, &1))

    required_issue =
      if has_live_view? do
        []
      else
        [
          format_issue(
            issue_meta,
            message: """
            Files in views/ folder must contain `use FirmowidWeb, :live_view`.
            This ensures LiveViews are only placed in views folders.
            """,
            line_no: 1,
            trigger: "views/"
          )
        ]
      end

    phoenix_issues ++ required_issue
  end

  # --- Components folder: must use :live_component or :html ---

  defp validate_components_folder(source_file, issue_meta) do
    uses = extract_uses(source_file)

    # Check for forbidden direct Phoenix usage
    phoenix_issues =
      uses
      |> Enum.filter(fn
        {:phoenix, :component, _} -> true
        {:phoenix, :live_component, _} -> true
        _ -> false
      end)
      |> Enum.map(fn
        {:phoenix, :component, line_no} ->
          format_issue(
            issue_meta,
            message: """
            Do not use `use Phoenix.Component` directly in components/ folder.
            Use `use FirmowidWeb, :html` instead to ensure consistent helpers.
            """,
            line_no: line_no,
            trigger: "Phoenix.Component"
          )

        {:phoenix, :live_component, line_no} ->
          format_issue(
            issue_meta,
            message: """
            Do not use `use Phoenix.LiveComponent` directly in components/ folder.
            Use `use FirmowidWeb, :live_component` instead to ensure consistent helpers.
            """,
            line_no: line_no,
            trigger: "Phoenix.LiveComponent"
          )
      end)

    # Check for required FirmowidWeb macro
    has_valid_use? =
      Enum.any?(uses, fn
        {:firmowid_web, :live_component, _} -> true
        {:firmowid_web, :html, _} -> true
        _ -> false
      end)

    required_issue =
      if has_valid_use? do
        []
      else
        [
          format_issue(
            issue_meta,
            message: """
            Files in components/ folder must contain `use FirmowidWeb, :live_component`
            or `use FirmowidWeb, :html`.
            This ensures components are only placed in components folders.
            """,
            line_no: 1,
            trigger: "components/"
          )
        ]
      end

    phoenix_issues ++ required_issue
  end

  # --- Controllers folder: must use :controller ---

  defp validate_controllers_folder(source_file, issue_meta) do
    uses = extract_uses(source_file)

    # Check for forbidden direct Phoenix usage
    phoenix_issues =
      uses
      |> Enum.filter(&match?({:phoenix, :controller, _}, &1))
      |> Enum.map(fn {:phoenix, :controller, line_no} ->
        format_issue(
          issue_meta,
          message: """
          Do not use `use Phoenix.Controller` directly in controllers/ folder.
          Use `use FirmowidWeb, :controller` instead to ensure consistent helpers.
          """,
          line_no: line_no,
          trigger: "Phoenix.Controller"
        )
      end)

    # Check for required FirmowidWeb macro
    has_controller? = Enum.any?(uses, &match?({:firmowid_web, :controller, _}, &1))

    required_issue =
      if has_controller? do
        []
      else
        [
          format_issue(
            issue_meta,
            message: """
            Files in controllers/ folder must contain `use FirmowidWeb, :controller`.
            This ensures controllers are only placed in controllers folders.
            """,
            line_no: 1,
            trigger: "controllers/"
          )
        ]
      end

    phoenix_issues ++ required_issue
  end

  # --- Utilities folder: must NOT use any FirmowidWeb or Phoenix macros ---

  defp validate_utilities_folder(source_file, issue_meta) do
    uses = extract_uses(source_file)

    # Check for any FirmowidWeb macro usage
    firmowid_issues =
      uses
      |> Enum.filter(&match?({:firmowid_web, _, _}, &1))
      |> Enum.map(fn {:firmowid_web, type, line_no} ->
        format_issue(
          issue_meta,
          message: """
          Files in utilities/ folder must NOT use any `use FirmowidWeb, :#{type}` macro.
          Utilities should be pure Elixir with no Phoenix dependencies.
          Move this module to views/, components/, or controllers/ as appropriate.
          """,
          line_no: line_no,
          trigger: "use FirmowidWeb, :#{type}"
        )
      end)

    # Check for direct Phoenix macro usage
    phoenix_issues =
      uses
      |> Enum.filter(&match?({:phoenix, _, _}, &1))
      |> Enum.map(fn
        {:phoenix, :live_view, line_no} ->
          format_issue(
            issue_meta,
            message: """
            Files in utilities/ folder must NOT use `Phoenix.LiveView`.
            Utilities should be pure Elixir with no Phoenix dependencies.
            Move this module to views/ folder.
            """,
            line_no: line_no,
            trigger: "Phoenix.LiveView"
          )

        {:phoenix, :controller, line_no} ->
          format_issue(
            issue_meta,
            message: """
            Files in utilities/ folder must NOT use `Phoenix.Controller`.
            Utilities should be pure Elixir with no Phoenix dependencies.
            Move this module to controllers/ folder.
            """,
            line_no: line_no,
            trigger: "Phoenix.Controller"
          )

        {:phoenix, type, line_no} ->
          format_issue(
            issue_meta,
            message: """
            Files in utilities/ folder must NOT use Phoenix macros.
            Utilities should be pure Elixir with no Phoenix dependencies.
            Detected: Phoenix.#{Macro.camelize(to_string(type))}
            """,
            line_no: line_no,
            trigger: "Phoenix.#{Macro.camelize(to_string(type))}"
          )
      end)

    firmowid_issues ++ phoenix_issues
  end

  # --- AST Extraction Helpers ---

  defp extract_uses(source_file) do
    source_file
    |> Credo.Code.prewalk(&find_use_statements/2, [])
    |> Enum.reverse()
  end

  # Pattern: use FirmowidWeb, :type (e.g., :live_view, :controller)
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:FirmowidWeb]}, type]} = ast, acc) when is_atom(type) do
    {ast, [{:firmowid_web, type, meta[:line]} | acc]}
  end

  # Pattern: use Phoenix.LiveView
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:Phoenix, :LiveView]}]} = ast, acc) do
    {ast, [{:phoenix, :live_view, meta[:line]} | acc]}
  end

  # Pattern: use Phoenix.Controller
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:Phoenix, :Controller]}]} = ast, acc) do
    {ast, [{:phoenix, :controller, meta[:line]} | acc]}
  end

  # Pattern: use Phoenix.Component
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:Phoenix, :Component]}]} = ast, acc) do
    {ast, [{:phoenix, :component, meta[:line]} | acc]}
  end

  # Pattern: use Phoenix.LiveComponent
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:Phoenix, :LiveComponent]}]} = ast, acc) do
    {ast, [{:phoenix, :live_component, meta[:line]} | acc]}
  end

  # Pattern: use Phoenix.HTML (legacy, but catch it)
  defp find_use_statements({:use, meta, [{:__aliases__, _, [:Phoenix, :HTML]}]} = ast, acc) do
    {ast, [{:phoenix, :html, meta[:line]} | acc]}
  end

  # Pattern: use OtherModule, :type (track for potential issues)
  defp find_use_statements({:use, meta, [{:__aliases__, _, parts}, type]} = ast, acc)
       when is_list(parts) and is_atom(type) do
    # Only track Phoenix modules we care about
    case parts do
      [:Phoenix | _] ->
        # Unknown Phoenix module - track generically
        module_name = parts |> Enum.drop(1) |> List.last() |> to_string() |> String.downcase()
        {ast, [{:phoenix, String.to_atom(module_name), meta[:line]} | acc]}

      _ ->
        {ast, acc}
    end
  end

  # Pattern: use OtherModule (bare)
  defp find_use_statements({:use, meta, [{:__aliases__, _, parts}]} = ast, acc) when is_list(parts) do
    case parts do
      [:Phoenix | _] ->
        # Bare Phoenix use - categorize by last part
        module_name = parts |> List.last() |> to_string() |> String.downcase()
        {ast, [{:phoenix, String.to_atom(module_name), meta[:line]} | acc]}

      _ ->
        {ast, acc}
    end
  end

  # Ignore all other AST nodes
  defp find_use_statements(ast, acc), do: {ast, acc}
end
