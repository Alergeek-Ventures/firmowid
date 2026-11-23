defmodule FirmowidWeb.Landing.Utilities.Guides do
  @moduledoc """
  Public guide articles, feature pages and help articles compiled from Markdown
  files in `priv/guides` (`/poradnik`), `priv/guides/funkcje` (`/funkcje`) and
  `priv/guides/pomoc` (`/pomoc`).

  Each file starts with YAML front matter (`title`, `description`, `published`,
  `updated` and, for guides and help articles, `category`; feature pages may add
  `landing` with `kicker`, `note`, `facts`, `match`, the transfers paired with
  invoices drawn in the hero, `split`, the bar showing where each 100 zł of
  revenue went, and `timer`, the running timer with the month's
  hours by project drawn there, for their landing layout); the file name is the
  URL slug. Guide categories, in display order, and the guide index heading and
  introduction are in `priv/guides/categories.yml` and `priv/guides/index.yml`;
  the help index heading, introduction and categories are in
  `priv/guides/pomoc/index.yml`. Images in the body get their dimensions
  and lazy loading. A PNG at `priv/static/images/guides/og/<slug>.png` (for
  feature and help pages `og/funkcje/<slug>.png` and `og/pomoc/<slug>.png`),
  when present, becomes the page's link preview image. The Markdown steps (Firmowid
  rows, FAQ) live in `FirmowidWeb.Landing.Utilities.GuideMarkdown`.
  """

  alias FirmowidWeb.Landing.Utilities.GuideMarkdown

  @type category :: %{slug: String.t(), name: String.t(), description: String.t()}

  @type image :: %{path: String.t(), width: pos_integer(), height: pos_integer()}

  @type section :: :guide | :feature | :help

  @type crumb :: %{name: String.t(), path: String.t()}

  @type guide :: %{
          slug: String.t(),
          section: section(),
          path: String.t(),
          breadcrumbs: [crumb()],
          title: String.t(),
          description: String.t(),
          published: Date.t(),
          updated: Date.t(),
          category: category() | nil,
          html: String.t(),
          faq: [GuideMarkdown.faq_entry()],
          image: image() | nil,
          layout: GuideMarkdown.feature_layout() | nil,
          landing: landing() | nil
        }

  @type landing :: %{
          kicker: String.t() | nil,
          note: String.t() | nil,
          author: :stanislaw | :franek,
          facts: [%{label: String.t(), value: String.t()}],
          match: [
            %{
              payer: String.t(),
              date: String.t(),
              amount: String.t(),
              invoice: String.t(),
              status: String.t(),
              suggested?: boolean()
            }
          ],
          timer:
            %{
              title: String.t(),
              project: String.t(),
              hours: non_neg_integer(),
              minutes: non_neg_integer(),
              seconds: non_neg_integer(),
              month: String.t(),
              total: String.t(),
              projects: [%{name: String.t(), hours: String.t(), share: pos_integer()}]
            }
            | nil,
          split:
            %{
              period: String.t(),
              left: pos_integer(),
              costs: [%{name: String.t(), share: pos_integer()}]
            }
            | nil
        }

  @guides_dir Application.app_dir(:firmowid, "priv/guides")
  @static_dir Application.app_dir(:firmowid, "priv/static")
  @categories_path Path.join(@guides_dir, "categories.yml")
  @index_path Path.join(@guides_dir, "index.yml")
  @help_index_path Path.join(@guides_dir, "pomoc/index.yml")
  @features_index_path Path.join(@guides_dir, "funkcje/index.yml")
  @patterns ["*.md", "funkcje/*.md", "pomoc/*.md"]
  @paths Enum.flat_map(@patterns, &(@guides_dir |> Path.join(&1) |> Path.wildcard()))

  @external_resource @categories_path
  @external_resource @index_path
  @external_resource @help_index_path
  @external_resource @features_index_path

  for path <- @paths do
    @external_resource path
  end

  # Recompile when a guide is added or removed, not only when one changes.
  def __mix_recompile__?, do: Enum.flat_map(@patterns, &(@guides_dir |> Path.join(&1) |> Path.wildcard())) != @paths

  @index_page @index_path
              |> YamlElixir.read_from_file!()
              |> then(
                &%{
                  heading: Map.fetch!(&1, "heading"),
                  intro: Map.fetch!(&1, "intro"),
                  read_next: Map.fetch!(&1, "read_next")
                }
              )

  to_category = fn category ->
    %{
      slug: Map.fetch!(category, "slug"),
      name: Map.fetch!(category, "name"),
      description: Map.fetch!(category, "description")
    }
  end

  @categories @categories_path |> YamlElixir.read_from_file!() |> Enum.map(to_category)

  help_index = YamlElixir.read_from_file!(@help_index_path)

  @help_index_page %{
    heading: Map.fetch!(help_index, "heading"),
    intro: Map.fetch!(help_index, "intro"),
    title: Map.fetch!(help_index, "title"),
    description: Map.fetch!(help_index, "description")
  }

  @help_categories help_index |> Map.fetch!("categories") |> Enum.map(to_category)

  features_index = YamlElixir.read_from_file!(@features_index_path)

  @feature_link_label Map.fetch!(features_index, "link_label")

  @feature_page features_index
                |> Map.fetch!("page")
                |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)

  # Section, URL prefix, breadcrumb root and categories of each directory.
  @sections %{
    "guides" => {:guide, "/poradnik", "Poradnik", @categories},
    "funkcje" => {:feature, "/funkcje", "Funkcje", []},
    "pomoc" => {:help, "/pomoc", Map.fetch!(help_index, "heading"), @help_categories}
  }

  @guides @paths
          |> Enum.map(fn path ->
            [_, front_matter, body] = Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, File.read!(path))
            meta = YamlElixir.read_from_string!(front_matter)
            slug = Path.basename(path, ".md")

            {section, root, root_name, categories} =
              Map.fetch!(@sections, path |> Path.dirname() |> Path.basename())

            category =
              if categories != [] do
                category_slug = Map.fetch!(meta, "category")

                Enum.find(categories, &(&1.slug == category_slug)) ||
                  raise("#{path}: unknown category #{inspect(category_slug)}")
              end

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
              |> GuideMarkdown.mark_firmowid_rows()

            og_path =
              if section == :guide,
                do: "/images/guides/og/#{slug}.png",
                else: "/images/guides/og#{root}/#{slug}.png"

            image =
              if File.exists?(Path.join(@static_dir, og_path)) do
                {width, height} = dimensions.(og_path)
                %{path: og_path, width: width, height: height}
              end

            title = Map.fetch!(meta, "title")

            # Who signs the quote under the hero; pages without `author` are signed by Stanisław.
            quote_author = fn
              nil -> :stanislaw
              "franek" -> :franek
            end

            landing = fn landing ->
              facts =
                Enum.map(
                  landing["facts"] || [],
                  &%{label: Map.fetch!(&1, "label"), value: Map.fetch!(&1, "value")}
                )

              match =
                Enum.map(
                  landing["match"] || [],
                  &%{
                    payer: Map.fetch!(&1, "payer"),
                    date: Map.fetch!(&1, "date"),
                    amount: Map.fetch!(&1, "amount"),
                    invoice: Map.fetch!(&1, "invoice"),
                    status: Map.fetch!(&1, "status"),
                    suggested?: &1["suggested"] == true
                  }
                )

              timer =
                if timer = landing["timer"] do
                  %{
                    title: Map.fetch!(timer, "title"),
                    project: Map.fetch!(timer, "project"),
                    hours: Map.fetch!(timer, "hours"),
                    minutes: Map.fetch!(timer, "minutes"),
                    seconds: Map.fetch!(timer, "seconds"),
                    month: Map.fetch!(timer, "month"),
                    total: Map.fetch!(timer, "total"),
                    projects:
                      Enum.map(
                        Map.fetch!(timer, "projects"),
                        &%{
                          name: Map.fetch!(&1, "name"),
                          hours: Map.fetch!(&1, "hours"),
                          share: Map.fetch!(&1, "share")
                        }
                      )
                  }
                end

              split =
                if split = landing["split"] do
                  %{
                    period: Map.fetch!(split, "period"),
                    left: Map.fetch!(split, "left"),
                    costs:
                      Enum.map(
                        Map.fetch!(split, "costs"),
                        &%{name: Map.fetch!(&1, "name"), share: Map.fetch!(&1, "share")}
                      )
                  }
                end

              %{
                kicker: landing["kicker"],
                note: landing["note"],
                author: quote_author.(landing["author"]),
                facts: facts,
                match: match,
                timer: timer,
                split: split
              }
            end

            %{
              slug: slug,
              section: section,
              path: "#{root}/#{slug}",
              breadcrumbs:
                [%{name: root_name, path: root}] ++
                  if(category,
                    do: [%{name: category.name, path: "#{root}##{category.slug}"}],
                    else: []
                  ),
              title: title,
              description: Map.fetch!(meta, "description"),
              published: Date.from_iso8601!(Map.fetch!(meta, "published")),
              updated: Date.from_iso8601!(Map.fetch!(meta, "updated")),
              category: category,
              html: html,
              faq: GuideMarkdown.faq(body),
              image: image,
              layout: if(section == :feature, do: GuideMarkdown.feature_layout(html)),
              landing: if(section == :feature, do: landing.(Map.get(meta, "landing") || %{})),
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

  @doc "Lists all guides of `/poradnik`, newest first."
  @spec all() :: [guide()]
  def all, do: in_section(:guide)

  @doc "Lists the pages of a section, newest first."
  @spec in_section(section()) :: [guide()]
  def in_section(section), do: Enum.filter(@guides, &(&1.section == section))

  @doc "Returns the heading and introduction of the guide index and the heading of the read-next list."
  @spec index_page() :: %{heading: String.t(), intro: String.t(), read_next: String.t()}
  def index_page, do: @index_page

  @doc "Returns the label of links from the /funkcje tiles to the feature pages."
  @spec feature_link_label() :: String.t()
  def feature_link_label, do: @feature_link_label

  @doc "Returns the fixed texts of the feature page layout (links, buttons, quote author)."
  @spec feature_page() :: %{atom() => String.t()}
  def feature_page, do: @feature_page

  @doc "Returns the heading, introduction, search title and description of the help index."
  @spec help_index_page() :: %{
          heading: String.t(),
          intro: String.t(),
          title: String.t(),
          description: String.t()
        }
  def help_index_page, do: @help_index_page

  @doc """
  Lists the categories of a section (`:guide` or `:help`) in display order with
  their pages, newest first, skipping empty ones.
  """
  @spec by_category(section()) :: [{category(), [guide()]}]
  def by_category(section \\ :guide) do
    categories = if section == :help, do: @help_categories, else: @categories
    pages = in_section(section)

    for category <- categories,
        guides = Enum.filter(pages, &(&1.category.slug == category.slug)),
        guides != [],
        do: {category, guides}
  end

  @doc """
  Lists `count` other guides to read after `guide`: the most recently updated
  ones from its category, then, if the category has too few, the most recently
  updated ones from the other categories.
  """
  @spec read_next(guide(), pos_integer()) :: [guide()]
  def read_next(guide, count \\ 3) do
    {same, other} =
      :guide
      |> in_section()
      |> Enum.reject(&(&1.slug == guide.slug))
      |> Enum.sort_by(& &1.updated, {:desc, Date})
      |> Enum.split_with(&(&1.category.slug == guide.category.slug))

    Enum.take(same ++ other, count)
  end

  @doc "Finds a page of a section by its slug."
  @spec fetch(String.t(), section()) :: {:ok, guide()} | :error
  def fetch(slug, section \\ :guide) do
    case Enum.find(@guides, &(&1.section == section and &1.slug == slug)) do
      nil -> :error
      guide -> {:ok, guide}
    end
  end
end
