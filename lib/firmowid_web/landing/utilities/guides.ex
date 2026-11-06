defmodule FirmowidWeb.Landing.Utilities.Guides do
  @moduledoc """
  Public guide articles compiled from Markdown files in `priv/guides`.

  Each file starts with YAML front matter (`title`, `description`, `published`,
  `updated`, `category`); the file name is the URL slug. Categories, in display
  order, are defined in `priv/guides/categories.yml`.
  """

  @type category :: %{slug: String.t(), name: String.t(), description: String.t()}

  @type guide :: %{
          slug: String.t(),
          title: String.t(),
          description: String.t(),
          published: Date.t(),
          updated: Date.t(),
          category: category(),
          html: String.t()
        }

  @guides_dir Application.app_dir(:firmowid, "priv/guides")
  @categories_path Path.join(@guides_dir, "categories.yml")
  @paths @guides_dir |> Path.join("*.md") |> Path.wildcard()

  @external_resource @categories_path

  for path <- @paths do
    @external_resource path
  end

  # Recompile when a guide is added or removed, not only when one changes.
  def __mix_recompile__?, do: @guides_dir |> Path.join("*.md") |> Path.wildcard() != @paths

  @categories @categories_path
              |> YamlElixir.read_from_file!()
              |> Enum.map(fn category ->
                %{
                  slug: Map.fetch!(category, "slug"),
                  name: Map.fetch!(category, "name"),
                  description: Map.fetch!(category, "description")
                }
              end)

  @guides @paths
          |> Enum.map(fn path ->
            [_, front_matter, body] = Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, File.read!(path))
            meta = YamlElixir.read_from_string!(front_matter)
            category_slug = Map.fetch!(meta, "category")

            %{
              slug: Path.basename(path, ".md"),
              title: Map.fetch!(meta, "title"),
              description: Map.fetch!(meta, "description"),
              published: Date.from_iso8601!(Map.fetch!(meta, "published")),
              updated: Date.from_iso8601!(Map.fetch!(meta, "updated")),
              category:
                Enum.find(@categories, &(&1.slug == category_slug)) ||
                  raise("#{path}: unknown guide category #{inspect(category_slug)}"),
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

  @doc "Lists categories in display order with their guides, newest first, skipping empty ones."
  @spec by_category() :: [{category(), [guide()]}]
  def by_category do
    for category <- @categories,
        guides = Enum.filter(@guides, &(&1.category.slug == category.slug)),
        guides != [],
        do: {category, guides}
  end

  @doc "Finds a guide by its slug."
  @spec fetch(String.t()) :: {:ok, guide()} | :error
  def fetch(slug) do
    case Enum.find(@guides, &(&1.slug == slug)) do
      nil -> :error
      guide -> {:ok, guide}
    end
  end
end
