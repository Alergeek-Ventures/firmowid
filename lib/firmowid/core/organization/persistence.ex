defmodule Firmowid.Core.Organization.Persistence do
  @moduledoc "PostgreSQL configuration for organizations, including their ParadeDB search index."
  use Spark.Dsl.Fragment, of: Ash.Resource, data_layer: AshPostgres.DataLayer

  postgres do
    table "organizations"
    repo Firmowid.Repo

    custom_statements do
      statement :organizations_paradedb_search_idx do
        up """
        CREATE INDEX IF NOT EXISTS organizations_search_idx
        ON organizations
        USING bm25 (id, name, nip)
        WITH (key_field='id', text_fields='{
          "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
          "nip": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 10, "prefix_only": true}}
        }');
        """

        down """
        DROP INDEX IF EXISTS organizations_search_idx;
        """
      end
    end
  end
end
