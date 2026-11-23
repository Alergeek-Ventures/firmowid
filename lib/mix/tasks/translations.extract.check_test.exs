defmodule Mix.Tasks.Translations.Extract.CheckTest do
  @moduledoc "Keeps the extraction cache context independent of runtime scheduler state."

  # Changes the VM-wide number of online schedulers.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Translations.Extract.Check

  test "the context does not change with the number of online schedulers" do
    online = :erlang.system_info(:schedulers_online)
    on_exit(fn -> :erlang.system_flag(:schedulers_online, online) end)
    version = :erlang.system_info(:system_version)
    context = Check.compiler_context()

    # A runner whose host moves CPUs between containers can start each VM with a different count.
    other = if online > 1, do: online - 1, else: min(2, :erlang.system_info(:schedulers))
    :erlang.system_flag(:schedulers_online, other)
    refute :erlang.system_info(:system_version) == version, "this VM has a single scheduler"

    assert Check.compiler_context() == context
  end
end
