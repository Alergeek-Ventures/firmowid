defmodule Firmowid.Repo.Migrations.CreateBm25Index do
  use Ecto.Migration

  def change do
    execute("""
      CREATE INDEX transactions_search_idx
      ON public.transactions
      USING bm25 (
        id,
        debtor_name,
        creditor_name,
        remittance_information_unstructured,
        transaction_currency
      )
      WITH (
        key_field = 'id',
        text_fields = '{
          "debtor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "creditor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "remittance_information_unstructured": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "transaction_currency": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}}
        }'
      );
    """)
  end
end
