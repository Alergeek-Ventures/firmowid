defmodule Firmowid.Repo.Migrations.CreateBm25IndexContractors do
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS contractors_search_idx;")

    execute("""
      CREATE INDEX contractors_search_idx
      ON public.contractors
      USING bm25 (
        id,
        display_name,
        name,
        surname,
        tax_id,
        email
      )
      WITH (
        key_field = 'id',
        text_fields = '{
          "display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
          "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
          "surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
          "tax_id": {"tokenizer": {"type": "keyword"}},
          "email": {"tokenizer": {"type": "default"}}
        }'
      );
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS contractors_search_idx;")
  end
end
