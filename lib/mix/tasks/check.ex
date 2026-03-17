defmodule Mix.Tasks.Check do
  @shortdoc "Runs all code quality checks with minimal output"
  @moduledoc """
  Runs all code quality checks for the project with minimal, clean output.

  Each check displays only its name and result (OK/FAIL). Full output is shown
  only when a check fails.

  ## Checks performed

  1. `mix compile --warnings-as-errors` - Compile with strict warnings
  2. `mix format --check-formatted` - Verify code formatting
  3. `mix deps.unlock --check-unused` - Check for unused dependencies
  4. `mix xref graph --label compile-connected --fail-above 1` - Check compile-time deps
  5. `mix credo --ignore refactor,design` - Static code analysis
  6. `mix sobelow --config` - Security vulnerability scanning
  7. `mix dialyzer` - Type checking
  8. `mix test` - Run test suite (skipped with --no-test)

  ## Usage

      mix check
      mix check --no-test   # Skip tests (for CI when tests run separately)
      mix check --verbose   # Show full output from all checks

  ## Options

      --verbose    Show full output from all checks
      --no-test    Skip running tests (useful in CI where tests run separately)
  """

  use Mix.Task

  @static_checks [
    {"Compiling", ["compile", "--warnings-as-errors"]},
    {"Format", ["format", "--check-formatted"]},
    {"Unused Deps", ["deps.unlock", "--check-unused"]},
    {"Xref", ["xref", "graph", "--label", "compile-connected", "--fail-above", "1"]},
    {"Credo", ["credo", "--ignore", "refactor,design"]},
    {"Sobelow", ["sobelow", "--config", "--compact"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  # Include :external tests locally — devs have third-party credentials.
  # CI runs plain `mix test` which excludes :external by default.
  @test_check {"Tests", ["test", "--include", "external"]}

  @impl Mix.Task
  def run(args) do
    verbose = "--verbose" in args
    skip_tests = "--no-test" in args

    checks =
      if skip_tests do
        @static_checks
      else
        @static_checks ++ [@test_check]
      end

    results =
      Enum.map(checks, fn {name, task_args} ->
        run_check(name, task_args, verbose)
      end)

    failed = Enum.filter(results, fn {_, status, _} -> status == :error end)

    IO.puts("")

    if failed == [] do
      IO.puts(IO.ANSI.green() <> "All checks passed." <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "#{length(failed)} check(s) failed." <> IO.ANSI.reset())
      System.halt(1)
    end
  end

  defp run_check(name, [task | args], verbose) do
    # Pad the name for aligned output
    padded_name = String.pad_trailing(name, 12)
    IO.write("#{padded_name} ")

    {result, output} = capture_task(task, args, verbose)

    case result do
      :ok ->
        IO.puts(IO.ANSI.green() <> "OK" <> IO.ANSI.reset())
        {name, :ok, output}

      :error ->
        IO.puts(IO.ANSI.red() <> "FAIL" <> IO.ANSI.reset())

        if !verbose do
          # Show the captured output on failure
          IO.puts("")
          IO.puts(output)
          IO.puts("")
        end

        {name, :error, output}
    end
  end

  defp capture_task(task, args, verbose) do
    if verbose do
      # In verbose mode, run directly and stream output
      IO.puts("")
      run_task_directly(task, args)
    else
      # Capture output using StringIO
      capture_task_output(task, args)
    end
  end

  defp run_task_directly(task, args) do
    Mix.Task.rerun(task, args)
    {:ok, ""}
  rescue
    e in Mix.Error ->
      {:error, Exception.message(e)}
  catch
    :exit, {:shutdown, 1} ->
      {:error, "Task failed"}

    :exit, _ ->
      {:error, "Task failed"}
  end

  defp capture_task_output(task, args) do
    # Capture IO output using StringIO as group leader
    original_gl = Process.group_leader()
    {:ok, capture_pid} = StringIO.open("")

    result = do_capture_task(task, args, original_gl, capture_pid)

    Process.group_leader(self(), original_gl)
    StringIO.close(capture_pid)

    result
  end

  defp do_capture_task(task, args, _original_gl, capture_pid) do
    Process.group_leader(self(), capture_pid)

    Mix.Task.rerun(task, args)

    {:ok, get_captured_output(capture_pid)}
  rescue
    e in Mix.Error ->
      output = get_captured_output(capture_pid)
      {:error, output <> "\n" <> Exception.message(e)}
  catch
    :exit, {:shutdown, 1} ->
      output = get_captured_output(capture_pid)
      {:error, output}

    :exit, _ ->
      output = get_captured_output(capture_pid)
      {:error, output}
  end

  defp get_captured_output(capture_pid) do
    {_input, output} = StringIO.contents(capture_pid)
    output
  end
end
