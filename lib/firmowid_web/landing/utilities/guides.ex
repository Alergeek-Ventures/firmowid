defmodule FirmowidWeb.Landing.Utilities.Guides do
  @moduledoc """
  Public guide articles compiled from Markdown files in `priv/guides`.

  Each file starts with YAML front matter (`title`, `description`, `published`,
  `updated`); the file name is the URL slug.
  """

  @type guide :: %{
          slug: String.t(),
          title: String.t(),
          description: String.t(),
          published: Date.t(),
          updated: Date.t(),
          html: String.t()
        }

  @guides_dir Application.app_dir(:firmowid, "priv/guides")
  @paths @guides_dir |> Path.join("*.md") |> Path.wildcard()

  for path <- @paths do
    @external_resource path
  end

  # Recompile when a guide is added or removed, not only when one changes.
  def __mix_recompile__?, do: @guides_dir |> Path.join("*.md") |> Path.wildcard() != @paths

  @guides @paths
          |> Enum.map(fn path ->
            [_, front_matter, body] = Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, File.read!(path))
            meta = YamlElixir.read_from_string!(front_matter)

            %{
              slug: Path.basename(path, ".md"),
              title: Map.fetch!(meta, "title"),
              description: Map.fetch!(meta, "description"),
              published: Date.from_iso8601!(Map.fetch!(meta, "published")),
              updated: Date.from_iso8601!(Map.fetch!(meta, "updated")),
              html:
                MDEx.to_html!(body,
                  extension: [table: true, tasklist: true, strikethrough: true, autolink: true],
                  render: [unsafe: false]
                )
            }
          end)
          |> Enum.sort_by(& &1.published, {:desc, Date})

  @doc "Lists all guides, newest first."
  @spec all() :: [guide()]
  def all, do: @guides

  @doc "Finds a guide by its slug."
  @spec fetch(String.t()) :: {:ok, guide()} | :error
  def fetch(slug) do
    case Enum.find(@guides, &(&1.slug == slug)) do
      nil -> :error
      guide -> {:ok, guide}
    end
  end
end
