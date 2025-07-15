# Transaction Search Migration to ParadeDB + Paradex

This document outlines the step-by-step plan to replace the current `ILIKE`-based implementation in `Finances.search_transactions/1` with a BM25 full-text search powered by ParadeDB and its Elixir wrapper **Paradex**.

---

## 1. Dependencies

1. **Add Paradex**
   ```elixir
   # mix.exs
   def deps do
     [
       {:paradex, "~> 0.4.0"}           # ParadeDB ≥ 0.15.x
     ]
   end
   ```
2. **Define custom Postgres types**
   ```elixir
   # lib/firmowid/postgrex_types.ex
   Postgrex.Types.define(
     Firmowid.PostgrexTypes,
     Pgvector.extensions() ++ Paradex.extensions() ++ Ecto.Adapters.Postgres.extensions(),
     []
   )
   ```
3. **Wire repo configuration**
   ```elixir
   # config/config.exs
   config :firmowid, Firmowid.Repo,
     types: Firmowid.PostgrexTypes
   ```

---

## 2. ParadeDB Runtime

The `paradedb` extension is already present in both the local Docker image _and_ the Neon production cluster, so no extra enablement is required beyond the idempotent migration in step&nbsp;3.
// Row-level multi-tenancy
The application keeps a single `public.transactions` table with an `organization_id` column. The `Firmowid.Repo.prepare_query/3` callback automatically injects `WHERE organization_id = ?`, so no schema-per-tenant work is needed.

---

## 3. Migrations

1. **Enable ParadeDB extension** (idempotent)
   ```elixir
   execute("CREATE EXTENSION IF NOT EXISTS paradedb;")
   ```
2. **Create BM25 covering index**
   ```elixir
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
     WITH (key_field = 'id');
   """)
   ```

---

## 4. Application Code Changes

Refactor `Finances.search_transactions/1`:

```elixir
def search_transactions(query) do
  import Paradex, only: [~>: 2]
  import Ecto.Query

  Transaction
  |> where([t],
       t.debtor_name                       ~> ^query or
       t.creditor_name                     ~> ^query or
       t.remittance_information_unstructured ~> ^query or
       t.transaction_currency              ~> ^query)
  # `paradedb.score(id)` returns the BM25 relevance.  The Repo layer still
  # enforces the per-tenant filter, so cross-org leakage is impossible.
  |> order_by(fragment("paradedb.score(?) DESC", t.id))
  |> limit(15)
  |> Repo.all()
end
```

No changes required for LiveViews or API controllers.

---

## 5. (Optional) pgvector-based semantic reranking

### 5.1 Rationale

BM25 excels at keyword matches but can miss fuzzy semantics (e.g. typos, related terms). Storing sentence embeddings of each transaction lets us

1. Catch semantic matches the user didn’t explicitly type.
2. Rerank BM25 candidates by cosine similarity for better relevance.

### 5.2 What to embed?

| Field                                 | Why                                                                                                      |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `debtor_name`                         | Name of the paying party – high user recall for search                                                   |
| `creditor_name`                       | Name of the receiving party – equally important                                                          |
| `remittance_information_unstructured` | Free-form payment description – often contains invoice numbers, project names, or natural-language notes |

`transaction_amount` & `currency` are numeric/short tokens; BM25 fast fields already handle them, so they’re **not** embedded.

For each row we’ll concatenate those fields into a single text like:

```
"#{debtor_name} → #{creditor_name}: #{remittance_information_unstructured}"
```

and embed that.

### 5.3 Implementation steps

1. **Dependencies**
   ```elixir
   {:openai, "~> 0.5"},       # or any embedding provider
   {:pgvector, "~> 0.3"}
   ```
2. **Migration**

   ```elixir
   execute("CREATE EXTENSION IF NOT EXISTS vector;")

   alter table(:transactions) do
     # 1536 dims for `text-embedding-3-small` (read from a constant to avoid drift)
     add :embedding, :vector, size: 1536
   end

   execute("""
     CREATE INDEX transactions_embedding_hnsw_idx
     ON public.transactions
     USING hnsw (embedding vector_cosine_ops)  -- cosine > l2 for embeddings
     WITH (m = 16, ef_construction = 64);
   """)
   ```

3. **Back-fill task** (`mix firmowid.embed_transactions`)
   - Stream rows missing `embedding` in batches of ≈ 96 (OpenAI cost-optimal).
   - Retry with exponential back-off on HTTP 429 / 5xx.
4. **Automatic embedding for new rows**
   - After `create_or_update_transactions/1`, enqueue an Oban job on the `:embeddings` queue (low concurrency, e.g. `max_demand: 2`).
5. **Query pipeline**
   ```elixir
   def semantic_rerank(query) do
     # 1. BM25 – fast candidate fetch
     ids = search_transactions(query) |> Enum.map(& &1.id)
     # 2. Embed the query once
     q_emb = Embeddings.encode!(query)
     # 3. Fetch top-N similar vectors among candidates
     sql = """
       SELECT id
       FROM transactions
       WHERE id = ANY($1)
       ORDER BY embedding <-> $2
       LIMIT 15
     """
     %{rows: rows} = Repo.query!(sql, [ids, q_emb])
     Repo.all(from t in Transaction, where: t.id in ^List.flatten(rows))
   end
   ```

## 6. Testing & Seed Data

### 6.1 End-to-End integration test

- **Goal:** Verify the complete search stack (Paradex → ParadeDB index) works from Elixir code to DB and back.
- **Approach:**
  1. Insert two contrived transactions via fixtures (e.g. one with `debtor_name: "Acme Corp"`).
  2. Call `Finances.search_transactions("Acme")` inside the test.
  3. Assert that exactly the expected record is returned and ranked first.
  4. Clean up inserted rows to keep DB state pristine.
- **Location:** `test/firmowid/finances_search_test.exs`.

### 6.2 Livebook performance notebook

- **Goal:** Provide an interactive environment to gauge search latency and relevance on larger, real-world datasets.
- **Notebook:** `finances/search_transactions.livemd`
- **Sections to include:**

  1. **Setup** – start Firmowid.Repo.
  2. **Synthetic bulk insert** – load ~10k random transactions.
  3. **Timing helpers** – wrapper that measures `Repo.all` execution time.
  4. **Query experiments** – set of queries that we want to test on.

- **Outcome:** developers can iterate on tokenizer/field options and immediately see impact on latency & relevance.

### Seed data

- Extend `priv/repo/seeds.exs` with a few representative transactions so local/dev envs have something to search against immediately.

---

## 7. Operations & Maintenance

- Refresh BM25 statistics periodically:

  ```sql
  VACUUM public.transactions;
  ```

  Not sure what the best way of doing that is.

- Inspect index health:
  ```sql
  SELECT * FROM paradedb.index_info('transactions_search_idx');
  ```
- Re-index after column changes with `CREATE INDEX CONCURRENTLY`.
