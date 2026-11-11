defmodule Firmowid.Core.Member.Persistence do
  @moduledoc "PostgreSQL configuration for members."
  use Spark.Dsl.Fragment, of: Ash.Resource, data_layer: AshPostgres.DataLayer

  postgres do
    table "members"
    repo Firmowid.Repo

    references do
      reference :user, on_delete: :delete
      reference :avatar_blob, on_delete: :nilify
    end
  end
end
