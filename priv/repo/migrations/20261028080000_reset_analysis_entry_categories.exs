defmodule Firmowid.Repo.Migrations.ResetAnalysisEntryCategories do
  @moduledoc """
  Drops the classifier's entry categories chosen before cost invoice seller
  names and descriptions were enriched with web search, so the hourly
  classification chooses them again from the better descriptions. The owner's
  confirmed counterparty categories stay.

  A data-only migration: Ash codegen generates schema changes only.
  """

  use Ecto.Migration

  def up do
    execute("DELETE FROM analysis_entry_categories")
  end

  def down, do: :ok
end
