defmodule Firmowid.Blobs.Checks.CanReadHolder do
  @moduledoc """
  Passes for a blob held by a record the actor may read, through any of the
  given relationships.

  Each relationship is the builtin `can_read/2` check; they are combined into
  one filter because the policy solver's work grows exponentially with the
  number of separate filter checks in a policy.
  """
  use Ash.Policy.FilterCheck

  alias Ash.Policy.Check.CanRead

  @impl true
  def describe(opts), do: "actor can read a record holding the file via #{inspect(opts[:relationships])}"

  @impl true
  def filter(actor, context, opts) do
    opts
    |> Keyword.fetch!(:relationships)
    |> Enum.map(&CanRead.filter(actor, context, relationship_path: [&1]))
    |> Enum.reduce(false, fn holder, acc -> expr(^acc or ^holder) end)
  end
end
