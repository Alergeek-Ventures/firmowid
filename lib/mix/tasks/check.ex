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
  4. `mix xref graph --label compile-connected` - Check compile-time dependency ceiling
  5. `mix credo --strict` - Static code analysis
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

  # Format and Tests both run as system commands (not Mix.Task.rerun).
  #
  # Format: Spark.Formatter's subdirectory plugin triggers internal compilation
  # that conflicts with the captured group leader used by Mix.Task.rerun, causing
  # Sourceror to appear unavailable during Spark's compile-time Code.ensure_loaded? check.
  #
  # Tests: ExUnit signals failures via System.at_exit (not System.halt or a raised
  # exception), so Mix.Task.rerun returns :ok even when tests fail — the at_exit
  # callback only fires when the OS process shuts down, which never happens inside
  # the running mix check process. Running as a subprocess gives us the real OS
  # exit code and prevents false "Tests OK" results.
  @cmd_checks [
    {"Format", ["format"]},
    {"Sobelow", ["sobelow", "--config", "--compact", "--private"]}
  ]

  @static_checks [
    {"Compiling", ["compile", "--warnings-as-errors"]},
    {"Unused Deps", ["deps.unlock", "--check-unused"]},
    # Keep as low as possible — Ash macro expansion inherently raises this ceiling over time.
    # Temporary ceiling agreed for the assistant refactor while preserving visibility.
    {"Xref", ["xref", "graph", "--label", "compile-connected", "--fail-above", "50"]},
    {"Credo", ["credo", "--strict"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  # Include :external tests locally — devs have third-party credentials.
  # CI runs plain `mix test` which excludes :external by default.
  # Must be a cmd check (subprocess) — see module comment above.
  @test_cmd_args ["test", "--include", "external"]

  @impl Mix.Task
  def run(args) do
    verbose = "--verbose" in args
    skip_tests = "--no-test" in args

    cmd_results =
      Enum.map(@cmd_checks, fn {name, task_args} ->
        run_cmd_check(name, task_args, verbose)
      end)

    static_results =
      Enum.map(@static_checks, fn {name, task_args} ->
        run_check(name, task_args, verbose)
      end)

    test_results =
      if skip_tests,
        do: [],
        else: [run_cmd_check("Tests", @test_cmd_args, verbose)]

    results = cmd_results ++ static_results ++ test_results

    failed = Enum.filter(results, fn {_, status, _} -> status == :error end)

    IO.puts("")

    if failed == [] do
      IO.puts(IO.ANSI.green() <> "All checks passed." <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "#{length(failed)} check(s) failed." <> IO.ANSI.reset())
      System.halt(1)
    end
  end

  defp run_cmd_check(name, [task | args], verbose) do
    padded_name = String.pad_trailing(name, 12)
    IO.write("#{padded_name} ")

    mix = System.find_executable("mix") || "mix"
    cmd_args = [task | args]

    {output, exit_code} = System.cmd(mix, cmd_args, stderr_to_stdout: true)

    case exit_code do
      0 ->
        IO.puts(IO.ANSI.green() <> "OK" <> IO.ANSI.reset())
        if verbose, do: IO.puts(output)
        {name, :ok, output}

      _ ->
        IO.puts(IO.ANSI.red() <> "FAIL" <> IO.ANSI.reset())

        if !verbose do
          IO.puts("")
          IO.puts(output)
          IO.puts("")
        end

        {name, :error, output}
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
