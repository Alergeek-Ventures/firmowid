defmodule Mix.Tasks.Check do
  @shortdoc "Runs code quality checks with timings and failure details"
  @moduledoc """
  Runs the project's full final verification without formatting source files.

  Strict compilation runs first, followed by inexpensive checks, translation
  extraction, Dialyzer and tests. Compilation failure skips checks that may
  implicitly compile; any failed prerequisite skips the remaining costly checks.
  Each executed check reports elapsed time and its real subprocess exit status.
  Each check uses one result line; child output is shown only on failure or with --verbose.

  ## Usage

      mix check
      mix check --quick     # Local loop: skip only extraction and Dialyzer
      mix check --no-test   # Tests are verified separately, for example in CI
      mix check --external  # Include tests calling real third-party APIs
      mix check --verbose   # Stream all child output, including successful checks

  Tests use plain `mix test` by default, which excludes tests tagged `:external`.
  Quick verification does not replace a full `mix check` before submitting changes.
  Unknown options and positional arguments are rejected.
  """

  use Mix.Task

  @cheap_checks [
    {"Format", ["format", "--check-formatted"]},
    {"Translations", ["translations.check"]},
    {"Unused Deps", ["deps.unlock", "--check-unused"]},
    {"Depscheck", ["depscheck"]},
    {"Credo", ["credo", "--strict"]},
    {"Sobelow", ["sobelow", "--config", "--compact", "--private"]},
    {"Npm licenses", ["assets.licenses"]}
  ]

  @full_checks [
    {"Translation extraction", ["gettext.extract", "--check-up-to-date"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  @impl Mix.Task
  @doc "Runs the selected verification checks and exits with the first failing child status."
  @spec run([String.t()]) :: :ok
  def run(args) do
    options = parse_options!(args)
    verbose = Keyword.get(options, :verbose, false)
    compilation = run_check("Compiling", ["compile", "--warnings-as-errors"], verbose)
    {_name, compile_status} = compilation

    cheap_results =
      Enum.map(@cheap_checks, fn {name, task_args} ->
        if compile_status == 0 do
          run_check(name, task_args, verbose)
        else
          skip_check(name, "compilation failed")
        end
      end)

    [compilation | cheap_results]
    |> run_remaining_checks(options)
    |> summarize()
  end

  defp parse_options!(args) do
    {options, rest} =
      OptionParser.parse!(args,
        strict: [quick: :boolean, test: :boolean, external: :boolean, verbose: :boolean]
      )

    if rest != [], do: Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")

    options
  end

  defp run_remaining_checks(results, options) do
    test_args =
      if Keyword.get(options, :external, false),
        do: ["test", "--include", "external"],
        else: ["test"]

    checks =
      Enum.map(@full_checks, fn {name, args} ->
        {name, args, Keyword.get(options, :quick, false), "--quick"}
      end) ++ [{"Tests", test_args, not Keyword.get(options, :test, true), "--no-test"}]

    Enum.reduce(checks, results, fn {name, args, omitted?, reason}, previous ->
      result =
        cond do
          omitted? -> skip_check(name, reason)
          failed?(previous) -> skip_check(name, "a prerequisite failed")
          true -> run_check(name, args, Keyword.get(options, :verbose, false))
        end

      previous ++ [result]
    end)
  end

  defp failed?(results) do
    Enum.any?(results, fn {_name, status} -> is_integer(status) and status != 0 end)
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
