defmodule FirmowidWeb.Landing.Utilities.Guides do
  @moduledoc """
  Public guide articles compiled from Markdown files in `priv/guides`.

  Each file starts with YAML front matter (`title`, `description`, `published`,
  `updated`, `category`); the file name is the URL slug. Categories, in display
  order, are defined in `priv/guides/categories.yml`. Images in the body get their
  dimensions and lazy loading. A PNG at `priv/static/images/guides/og/<slug>.png`,
  when present, becomes the guide's link preview image.
  """

  @type category :: %{slug: String.t(), name: String.t(), description: String.t()}

  @type image :: %{path: String.t(), width: pos_integer(), height: pos_integer()}

  @type guide :: %{
          slug: String.t(),
          title: String.t(),
          description: String.t(),
          published: Date.t(),
          updated: Date.t(),
          category: category(),
          html: String.t(),
          image: image() | nil
        }

  @guides_dir Application.app_dir(:firmowid, "priv/guides")
  @static_dir Application.app_dir(:firmowid, "priv/static")
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
            slug = Path.basename(path, ".md")

            dimensions = fn static_path ->
              image = Image.open!(Path.join(@static_dir, static_path))
              {Image.width(image), Image.height(image)}
            end

            html =
              body
              |> MDEx.to_html!(
                extension: [table: true, tasklist: true, strikethrough: true, autolink: true],
                render: [unsafe: false]
              )
              |> then(
                &Regex.replace(~r/<img src="(\/images\/guides\/[^"]+)"/, &1, fn _, src ->
                  {width, height} = dimensions.(src)

                  ~s(<img src="#{src}" width="#{width}" height="#{height}" loading="lazy" decoding="async")
                end)
              )

            og_path = "/images/guides/og/#{slug}.png"

            image =
              if File.exists?(Path.join(@static_dir, og_path)) do
                {width, height} = dimensions.(og_path)
                %{path: og_path, width: width, height: height}
              end

            %{
              slug: slug,
              title: Map.fetch!(meta, "title"),
              description: Map.fetch!(meta, "description"),
              published: Date.from_iso8601!(Map.fetch!(meta, "published")),
              updated: Date.from_iso8601!(Map.fetch!(meta, "updated")),
              category:
                Enum.find(@categories, &(&1.slug == category_slug)) ||
                  raise("#{path}: unknown guide category #{inspect(category_slug)}"),
              html: html,
              image: image
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
