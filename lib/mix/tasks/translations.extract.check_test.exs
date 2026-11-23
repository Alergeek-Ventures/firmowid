defmodule Mix.Tasks.Translations.Extract.CheckTest do
  @moduledoc "Keeps the extraction cache context independent of runtime scheduler state."

  # Changes the VM-wide number of online schedulers.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Translations.Extract.Check

  test "the context does not change with the number of online schedulers" do
    online = :erlang.system_info(:schedulers_online)
    on_exit(fn -> :erlang.system_flag(:schedulers_online, online) end)
    context = Check.compiler_context()

    # A runner whose host moves CPUs between containers starts each VM with a different count.
    :erlang.system_flag(:schedulers_online, max(online - 1, 1))

    assert Check.compiler_context() == context
  end
end
