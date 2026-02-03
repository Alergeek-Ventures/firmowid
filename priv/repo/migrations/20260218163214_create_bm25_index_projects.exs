defmodule Firmowid.Repo.Migrations.CreateBm25IndexProjects do
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS projects_search_idx;")

    execute("""
      CREATE INDEX projects_search_idx
      ON public.projects
      USING bm25 (
        id,
        name
      )
      WITH (
        key_field = 'id',
        text_fields = '{
          "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}}
        }'
      );
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS projects_search_idx;")
  end
end
