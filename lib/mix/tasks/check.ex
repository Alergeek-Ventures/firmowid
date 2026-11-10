defmodule Mix.Tasks.Check do
  @shortdoc "Runs code quality checks with timings and failure details"
  @moduledoc """
  Runs the local verification loop without formatting source files.

  Strict compilation runs first. Formatting and Credo then check only the files
  changed since the merge base with `origin/main`, followed by the translation
  catalog check and tests. Compilation failure skips the remaining checks, which
  would compile implicitly; any other failure still runs every remaining check,
  so one run reports all problems. Each executed check reports elapsed time and
  its real subprocess exit status. Child output is shown only on failure or with
  --verbose.

  Dialyzer, translation extraction, Sobelow, design tokens, the dependency
  audits and full-tree formatting and Credo run only in CI, the final gate.

  ## Usage

      mix check
      mix check --no-test   # Tests are verified separately
      mix check --external  # Include tests calling real third-party APIs
      mix check --verbose   # Stream all child output, including successful checks

  Tests use plain `mix test` by default, which excludes tests tagged `:external`.
  Unknown options and positional arguments are rejected.
  """

  use Mix.Task

  # A change under these paths can alter the result for files that did not change.
  @format_config_paths [".formatter.exs", "mix.lock"]
  @credo_config_paths [".credo.exs", "checks/", "mix.lock"]

  @impl Mix.Task
  @doc "Runs the selected verification checks and exits with the first failing child status."
  @spec run([String.t()]) :: :ok
  def run(args) do
    options = parse_options!(args)
    verbose = Keyword.get(options, :verbose, false)
    compilation = run_check("Compiling", ["compile", "--warnings-as-errors"], verbose)

    results =
      case compilation do
        {_name, 0} ->
          options
          |> selected_checks()
          |> Enum.map(fn
            {name, {:skip, reason}} -> skip_check(name, reason)
            {name, task_args} -> run_check(name, task_args, verbose)
          end)

        _failed ->
          options
          |> selected_checks()
          |> Enum.map(fn {name, _} -> skip_check(name, "compilation failed") end)
      end

    summarize([compilation | results])
  end

  defp parse_options!(args) do
    {options, rest} =
      OptionParser.parse!(args,
        strict: [test: :boolean, external: :boolean, verbose: :boolean]
      )

    if rest != [], do: Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")

    options
  end

  defp selected_checks(options) do
    changed = changed_files()

    test_check =
      cond do
        not Keyword.get(options, :test, true) -> {"Tests", {:skip, "--no-test"}}
        Keyword.get(options, :external, false) -> {"Tests", ["test", "--include", "external"]}
        true -> {"Tests", ["test"]}
      end

    [
      {"Format",
       scoped_args(
         ["format", "--check-formatted"],
         changed,
         @format_config_paths,
         &format_input?/1
       )},
      {"Translations", ["translations.check"]},
      {"Credo", scoped_args(["credo", "--strict"], changed, @credo_config_paths, &credo_input?/1)},
      test_check
    ]
  end

  # Checks every file when the scope is unknown or a shared configuration changed.
  defp scoped_args(task_args, :all, _config_paths, _input?), do: task_args

  defp scoped_args(task_args, changed, config_paths, input?) do
    config_changed? = Enum.any?(changed, &String.starts_with?(&1, config_paths))

    case Enum.filter(changed, input?) do
      _files when config_changed? -> task_args
      [] -> {:skip, "no changed files"}
      files -> task_args ++ files
    end
  end

  defp format_input?(path) do
    Path.extname(path) in [".ex", ".exs", ".heex"] and
      (Path.dirname(path) == "." or
         String.starts_with?(path, ["config/", "lib/", "priv/", "scripts/"]))
  end

  # Credo's default scope; migrations, seeds and config are not linted in CI either.
  defp credo_input?(path), do: Path.extname(path) in [".ex", ".exs"] and String.starts_with?(path, "lib/")

  # Committed, staged, unstaged and untracked changes since the branch left main.
  # Without a merge base (for example no origin/main), every file is checked.
  defp changed_files do
    with {:ok, base} <- git(["merge-base", "HEAD", "origin/main"]),
         {:ok, diff} <- git(["diff", "--name-only", "--diff-filter=d", String.trim(base)]),
         {:ok, untracked} <- git(["ls-files", "--others", "--exclude-standard"]) do
      String.split(diff <> untracked, "\n", trim: true)
    else
      :error -> :all
    end
  end

  defp git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _status} -> :error
    end
  end

  defp skip_check(name, reason) do
    IO.puts("#{String.pad_trailing(name, 22)} SKIP (#{reason}; not run)")
    {name, :skipped}
  end

  defp run_check(name, args, verbose) do
    padded_name = String.pad_trailing(name, 22)
    IO.write("#{padded_name} ")
    started_at = System.monotonic_time(:millisecond)

    # This is a Mix task, not application code; children must use its selected environment.
    # credo:disable-for-next-line Credo.Check.Warning.MixEnv
    command_options = [stderr_to_stdout: true, env: [{"MIX_ENV", Atom.to_string(Mix.env())}]]

    command_options =
      if verbose do
        IO.puts("(progress below)")
        Keyword.put(command_options, :into, IO.stream(:stdio, :line))
      else
        command_options
      end

    # Separate VMs preserve ExUnit's at_exit status and isolate Dialyzer's halt,
    # formatter compilation and task state without replacing the group leader.
    {output, exit_code} =
      System.cmd(System.find_executable("mix") || "mix", args, command_options)

    elapsed = Float.round((System.monotonic_time(:millisecond) - started_at) / 1000, 1)
    if verbose, do: IO.write("#{padded_name} ")

    if exit_code == 0 do
      IO.puts(IO.ANSI.green() <> "OK (#{elapsed}s)" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "FAIL (exit #{exit_code}; #{elapsed}s)" <> IO.ANSI.reset())
      if not verbose, do: IO.puts("\n#{output}")
    end

    {name, exit_code}
  end

  defp summarize(results) do
    failures = Enum.filter(results, fn {_name, status} -> is_integer(status) and status != 0 end)
    skipped = Enum.count(results, fn {_name, status} -> status == :skipped end)
    IO.puts("")

    case failures do
      [] ->
        IO.puts(IO.ANSI.green() <> "All selected checks passed (#{skipped} skipped)." <> IO.ANSI.reset())

      [{_name, exit_code} | _] ->
        IO.puts(
          IO.ANSI.red() <>
            "#{length(failures)} check(s) failed (#{skipped} skipped)." <> IO.ANSI.reset()
        )

        System.halt(exit_code)
    end
  end
end
