defmodule Mix.Tasks.Diag.Gettext do
  @moduledoc false
  # DIAGNOSTIC ONLY, never merge. Writes short digests (never values) of every input the
  # extraction cache and Mix's full-recompile decision depend on, so CI runs can be diffed.
  use Mix.Task

  alias Mix.Tasks.Loadconfig

  @parts ~w(system_version otp mix_path mix_env target project_config compiler_options firmowid_env gettext_env environment)

  def dump_context(parts, environment) do
    case System.get_env("GETTEXT_DIAG_DIR") do
      nil ->
        :ok

      dir ->
        lines =
          @parts
          |> Enum.zip(parts)
          |> Enum.flat_map(fn
            {"environment", _hash} ->
              Enum.map(environment, fn {k, v} -> "environment #{k} #{h(v)}" end)

            {name, value} when is_list(value) ->
              Enum.map(value, &keyed(name, &1))

            {name, value} ->
              ["#{name} - #{h(value)}"]
          end)

        write(dir, "ctx", lines)
    end
  end

  defp keyed(name, {key, value}), do: "#{name} #{inspect(key)} #{h(value)}"
  defp keyed(name, value), do: "#{name} item #{h(value)}"

  @impl Mix.Task
  def run([label]) do
    Mix.Task.run("loadconfig")
    manifest = hd(Mix.Tasks.Compile.Elixir.manifests())

    {_vsn, _modules, _sources, _exports, parents, cache_key, cwd, deps_config, project_mtime, config_mtime, _protocols} =
      manifest |> File.read!() |> :erlang.binary_to_term()

    current_lock = Mix.Dep.Lock.read() |> Map.take(Mix.Project.deps_apps()) |> Enum.sort()

    lines =
      [
        "label #{label}",
        "manifest_mtime #{Mix.Utils.last_modified(manifest)}",
        "config_mtime stored=#{config_mtime} current=#{Mix.Project.config_mtime()}",
        "project_mtime stored=#{project_mtime} current=#{Mix.Utils.last_modified(Mix.Project.project_file())}",
        "cwd_same #{cwd == File.cwd!()}",
        "cache_key #{h(cache_key)}",
        "parents #{h(parents)}",
        "local stored=#{h(deps_config.local)}",
        "dbg stored=#{h(deps_config.dbg)} current=#{h(Application.fetch_env!(:elixir, :dbg_callback))}",
        "lock stored=#{h(deps_config.lock)} current=#{h(current_lock)}"
      ] ++
        Enum.map(Mix.Project.config_files(), &"config_file #{&1} #{Mix.Utils.last_modified(&1)}") ++
        Enum.map(deps_config.config, fn {app, kw} -> "compile_config stored #{app} #{h(kw)}" end) ++
        Enum.map(Enum.sort(Loadconfig.read_compile()), fn {app, kw} ->
          "compile_config current #{app} #{h(kw)}"
        end) ++
        Enum.flat_map(deps_config.config, fn {app, kw} ->
          Enum.map(kw, fn {k, v} -> "compile_key stored #{app}.#{inspect(k)} #{h(v)}" end)
        end) ++
        Enum.flat_map(Enum.sort(Loadconfig.read_compile()), fn {app, kw} ->
          Enum.map(kw, fn {k, v} -> "compile_key current #{app}.#{inspect(k)} #{h(v)}" end)
        end)

    write(System.fetch_env!("GETTEXT_DIAG_DIR"), "manifest-#{label}", lines)
  end

  defp write(dir, prefix, lines) do
    File.mkdir_p!(dir)
    name = "#{prefix}-#{System.os_time(:nanosecond)}.txt"
    File.write!(Path.join(dir, name), Enum.join(lines, "\n") <> "\n")
  end

  defp h(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 10)
  end
end
