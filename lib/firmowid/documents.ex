defmodule Firmowid.Documents do
  import Ecto.Query, warn: false

  alias Firmowid.Repo
  alias Firmowid.Documents.Document

  def list_documents() do
    Document
    |> order_by(desc: :issue_date)
    |> Repo.all()
  end

  def create_document(attrs \\ %{}) do
    %Document{}
    |> Firmowid.Documents.Document.changeset(attrs)
    |> Repo.insert()
  end
end
