defmodule FirmowidWeb.Landing.Utilities.Guides do
  @moduledoc """
  Public guide articles compiled from Markdown files in `priv/guides`.

  Each file starts with YAML front matter (`title`, `description`, `published`,
  `updated`); the file name is the URL slug. Images in the body get their
  dimensions and lazy loading. A PNG at `priv/static/images/guides/og/<slug>.png`,
  when present, becomes the guide's link preview image.
  """

  @type image :: %{path: String.t(), width: pos_integer(), height: pos_integer()}

  @type guide :: %{
          slug: String.t(),
          title: String.t(),
          description: String.t(),
          published: Date.t(),
          updated: Date.t(),
          html: String.t(),
          image: image() | nil
        }

  @guides_dir Application.app_dir(:firmowid, "priv/guides")
  @static_dir Application.app_dir(:firmowid, "priv/static")
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
            slug = Path.basename(path, ".md")

            dimensions = fn static_path ->
              # Read the bytes so libvips cannot serve dimensions cached from an earlier version of the file.
              image =
                @static_dir |> Path.join(static_path) |> File.read!() |> Image.from_binary!()

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
              html: html,
              image: image,
              # Body images and the preview path (even when missing) recompile this module when they change.
              resources:
                [Path.join(@static_dir, og_path)] ++
                  for(
                    [_, src] <- Regex.scan(~r/<img src="([^"]+)"/, html),
                    do: Path.join(@static_dir, src)
                  )
            }
          end)
          |> Enum.sort_by(& &1.published, {:desc, Date})

  for guide <- @guides, resource <- guide.resources do
    @external_resource resource
  end

  @guides Enum.map(@guides, &Map.delete(&1, :resources))

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
