defmodule Firmowid.Translations.ExtractionCache do
  @moduledoc """
  Remembers successful, read-only Gettext extraction verification in the build directory.

  This is not a catalog cache: POT and PO files are never written. Git supplies
  the worktree inventory, but current file contents (not index blobs or HEAD)
  determine the fingerprint. Ignored Gettext catalogs are included explicitly.
  Unavailable fingerprints and invalid markers always fall back to the check.

  Environment and compiler configuration contribute only in-memory digests;
  the marker contains only a version and SHA-256 fingerprint, never their values.
  A changing worktree is not cached. Atomic publication prevents partial markers
  across concurrent CLI invocations; this does not lock developers' source edits.
  """

  @marker_version "gettext-extraction-v1:"

  @doc """
  Runs `check` unless an unchanged successful verification can be reused.

  Requires `:root`, `:build_path` and a zero-arity `:context` callback returning
  compiler/toolchain inputs. `:force` bypasses reuse. The check must return `:ok`
  or `{:error, reason}`; its errors and exceptions are preserved, never cached.
  Cache filesystem failures do not affect authoritative verification.
  """
  @spec run(keyword(), (-> :ok | {:error, term()})) :: :cached | :checked | {:error, term()}
  def run(options, check) do
    marker = Path.join(Keyword.fetch!(options, :build_path), ".gettext-extraction-check")
    before = fingerprint(options)

    if not Keyword.get(options, :force, false) and reusable?(marker, before, options) do
      :cached
    else
      discard_marker(marker)

      case check.() do
        :ok ->
          save_success(marker, before, options)
          :checked

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc "Computes a content fingerprint, or returns an error when inventory or reads are unavailable."
  @spec fingerprint(keyword()) :: {:ok, String.t()} | {:error, term()}
  def fingerprint(options) do
    root = Keyword.fetch!(options, :root)
    context = Keyword.fetch!(options, :context)

    with {:ok, paths} <- inventory(root),
         :ok <- check_directories(root, paths),
         {:ok, files} <- file_hashes(root, paths) do
      {:ok, digest({@marker_version, Path.expand(root), context.(), files})}
    end
  rescue
    _error in [ArgumentError, ErlangError, File.Error] -> {:error, :fingerprint_unavailable}
  end

  defp inventory(root) do
    with :ok <- check_git_root(root),
         {:ok, source} <- git_files(root, ["--cached", "--others", "--exclude-standard"]),
         {:ok, catalogs} <-
           git_files(root, ["--others", "--ignored", "--exclude-standard", "--", "priv/gettext"]) do
      catalogs = Enum.filter(catalogs, &(Path.extname(&1) in [".pot", ".po"]))
      {:ok, Enum.sort(Enum.uniq(source ++ catalogs))}
    end
  end

  defp check_git_root(root) do
    case System.cmd("git", ["rev-parse", "--show-prefix"], cd: root, stderr_to_stdout: true) do
      {"\n", 0} -> :ok
      _result -> {:error, :not_worktree_root}
    end
  end

  defp git_files(root, arguments) do
    case System.cmd("git", ["ls-files", "-z" | arguments], cd: root, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.split(output, <<0>>, trim: true)}
      {_output, status} -> {:error, {:git_inventory, status}}
    end
  end

  defp file_hashes(root, paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, hashes} ->
      case file_hash(Path.join(root, path)) do
        {:ok, hash} -> {:cont, {:ok, [{path, hash} | hashes]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_directories(root, paths) do
    paths
    |> Enum.flat_map(&parent_directories/1)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn directory, :ok ->
      case File.lstat(Path.join(root, directory)) do
        {:ok, %File.Stat{type: :directory}} -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        _result -> {:halt, {:error, :unsupported_directory}}
      end
    end)
  end

  defp parent_directories(path) do
    case Path.dirname(path) do
      "." -> []
      parent -> [parent | parent_directories(parent)]
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Paths come from the local Git inventory, not web input. Symlinks and other
  # non-regular files disable reuse rather than reading outside the worktree.
  defp file_hash(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} ->
        case File.read(path) do
          {:ok, contents} -> {:ok, {mode, digest(contents)}}
          {:error, reason} -> {:error, reason}
        end

      {:error, :enoent} ->
        {:ok, :missing}

      {:ok, _stat} ->
        {:error, :unsupported_file_type}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Marker paths are local CLI build paths, never web-controlled input.
  defp reusable?(marker, {:ok, hash} = before, options) do
    File.read(marker) == {:ok, @marker_version <> hash} and fingerprint(options) == before
  end

  defp reusable?(_marker, {:error, _reason}, _options), do: false

  # sobelow_skip ["Traversal.FileModule"]
  # Deletes only this task's disposable marker under the local build directory.
  defp discard_marker(marker) do
    _ = File.rm(marker)
    :ok
  end

  defp save_success(marker, {:ok, hash} = before, options) do
    if fingerprint(options) == before, do: publish_marker(marker, hash, before, options)
    :ok
  end

  defp save_success(_marker, {:error, _reason}, _options), do: :ok

  # sobelow_skip ["Traversal.FileModule"]
  # Writes only a digest to a uniquely named sibling in the CLI build directory.
  # The source and translation catalogs are never modified by this cache.
  defp publish_marker(marker, hash, before, options) do
    temporary = marker <> ".#{System.pid()}.#{System.unique_integer([:positive])}"

    try do
      with :ok <- File.mkdir_p(Path.dirname(marker)),
           :ok <- File.write(temporary, @marker_version <> hash, [:exclusive]),
           ^before <- fingerprint(options) do
        _ = File.rename(temporary, marker)
      end

      :ok
    after
      _ = File.rm(temporary)
    end
  end
end
