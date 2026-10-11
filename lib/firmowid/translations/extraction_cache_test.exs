defmodule Firmowid.Translations.ExtractionCacheTest do
  @moduledoc "Focused verification-cache tests using isolated Git worktrees and stub extraction."

  use ExUnit.Case, async: true

  alias Firmowid.Translations.ExtractionCache

  @moduletag :tmp_dir

  setup %{tmp_dir: directory} do
    root = Path.join(directory, "repository")
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "priv/gettext/pl/LC_MESSAGES"))
    git!(root, ["init", "--quiet"])

    File.write!(
      Path.join(root, ".gitignore"),
      "/_build/\n/priv/gettext/pl/LC_MESSAGES/default.po\n"
    )

    File.write!(Path.join(root, "lib/source.ex"), "initial source\n")
    File.write!(Path.join(root, "priv/gettext/default.pot"), "initial POT\n")
    git!(root, ["add", "."])

    options = [
      root: root,
      build_path: Path.join(root, "_build/test"),
      context: fn -> :fixture end
    ]

    %{root: root, options: options}
  end

  test "successful reuse and force bypass", %{options: options} do
    check = fn ->
      send(self(), :checked)
      :ok
    end

    assert ExtractionCache.run(options, check) == :checked
    assert_received :checked
    assert ExtractionCache.run(options, check) == :cached
    refute_received :checked
    assert ExtractionCache.run(Keyword.put(options, :force, true), check) == :checked
    assert_received :checked
    assert ExtractionCache.run(options, check) == :cached
  end

  test "current dirty, staged, new, renamed and deleted files invalidate", %{
    root: root,
    options: options
  } do
    check = fn -> :ok end
    assert ExtractionCache.run(options, check) == :checked

    File.write!(Path.join(root, "lib/source.ex"), "unstaged source\n")
    assert ExtractionCache.run(options, check) == :checked
    git!(root, ["add", "lib/source.ex"])
    File.write!(Path.join(root, "lib/source.ex"), "new working contents after staging\n")
    assert ExtractionCache.run(options, check) == :checked

    File.write!(Path.join(root, "lib/new.ex"), "new untracked module\n")
    assert ExtractionCache.run(options, check) == :checked
    File.rename!(Path.join(root, "lib/new.ex"), Path.join(root, "lib/renamed.ex"))
    assert ExtractionCache.run(options, check) == :checked
    git!(root, ["mv", "lib/source.ex", "lib/moved.ex"])
    assert ExtractionCache.run(options, check) == :checked
    File.rm!(Path.join(root, "lib/moved.ex"))
    assert ExtractionCache.run(options, check) == :checked
    assert ExtractionCache.run(options, check) == :cached
  end

  test "POT, ignored managed PO and compiler context invalidate", %{root: root, options: options} do
    check = fn -> :ok end
    assert ExtractionCache.run(options, check) == :checked
    File.write!(Path.join(root, "priv/gettext/default.pot"), "changed POT\n")
    assert ExtractionCache.run(options, check) == :checked
    po = Path.join(root, "priv/gettext/pl/LC_MESSAGES/default.po")
    File.write!(po, "ignored managed PO\n")
    assert ExtractionCache.run(options, check) == :checked
    File.write!(po, "changed ignored PO\n")
    assert ExtractionCache.run(options, check) == :checked
    File.rm!(po)
    assert ExtractionCache.run(options, check) == :checked
    changed = Keyword.put(options, :context, fn -> :changed_environment end)
    assert ExtractionCache.run(changed, check) == :checked
  end

  test "failures retain the original error and cannot reuse an earlier marker", %{
    options: options
  } do
    assert ExtractionCache.run(options, fn -> :ok end) == :checked
    forced = Keyword.put(options, :force, true)

    assert ExtractionCache.run(forced, fn -> {:error, :original_failure} end) ==
             {:error, :original_failure}

    assert_raise Mix.Error, "original extraction error", fn ->
      ExtractionCache.run(options, fn -> Mix.raise("original extraction error") end)
    end

    assert ExtractionCache.run(options, fn -> :ok end) == :checked
  end

  test "invalid markers, unavailable inventory and edits during verification are not cached", %{
    root: root,
    options: options
  } do
    check = fn -> :ok end
    assert ExtractionCache.run(options, check) == :checked
    marker = Path.join(Keyword.fetch!(options, :build_path), ".gettext-extraction-check")
    File.write!(marker, "invalid marker")
    assert ExtractionCache.run(options, check) == :checked

    assert ExtractionCache.run(Keyword.put(options, :force, true), fn ->
             File.write!(Path.join(root, "lib/source.ex"), "edited during extraction\n")
             :ok
           end) == :checked

    assert ExtractionCache.run(options, check) == :checked
    unavailable = Keyword.put(options, :root, Path.join(root, "does-not-exist"))
    assert ExtractionCache.run(unavailable, check) == :checked
    assert ExtractionCache.run(unavailable, check) == :checked
  end

  defp git!(root, arguments) do
    assert {_output, 0} = System.cmd("git", arguments, cd: root, stderr_to_stdout: true)
  end
end
