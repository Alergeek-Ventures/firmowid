defmodule FirmowidWeb.Landing.Utilities.GuideMarkdown do
  @moduledoc """
  Pure steps that turn a guide's Markdown and HTML into what the guide page and
  its structured data need. `FirmowidWeb.Landing.Utilities.Guides` calls them at
  compile time.
  """

  @type faq_entry :: %{question: String.t(), answer: String.t()}

  @faq_heading "Najczęstsze pytania"

  @doc """
  Marks comparison table rows that start with Firmowid, so the page can set them apart.
  """
  @spec mark_firmowid_rows(String.t()) :: String.t()
  def mark_firmowid_rows(html) do
    Regex.replace(~r/<tr>(\s*<td>(?:<strong>)?Firmowid)/, html, ~S(<tr class="firmowid">\1))
  end

  @doc """
  Reads the questions under `## #{@faq_heading}`, one `###` heading each, as plain
  text for FAQPage data. Images, single-line italic captions and link targets are
  left out of the answers; bold text and lists stay.
  """
  @spec faq(String.t()) :: [faq_entry()]
  def faq(markdown) do
    case Regex.run(~r/^## #{@faq_heading}\n(.*?)(?=^## |\z)/msu, markdown) do
      [_, section] ->
        for [_, question, answer] <-
              Regex.scan(~r/^### ([^\n]+)\n(.*?)(?=^### |\z)/msu, section) do
          %{question: String.trim(question), answer: plain_answer(answer)}
        end

      nil ->
        []
    end
  end

  @type feature_layout :: %{
          hero: %{src: String.t(), width: String.t(), height: String.t(), alt: String.t()} | nil,
          intro: String.t(),
          sections: [
            %{
              id: String.t(),
              title: String.t(),
              html: String.t(),
              faq?: boolean(),
              band?: boolean(),
              wide?: boolean()
            }
          ]
        }

  @image ~r/<p><img src="([^"]+)" width="(\d+)" height="(\d+)"[^>]*? alt="([^"]*)"[^>]*\/?><\/p>\n?/

  @doc """
  Splits a feature page's HTML for its landing layout: the first image becomes
  the hero picture, the text before the first `<h2>` the quoted introduction,
  and each `<h2>` a section. Images in sections get their alt text as a caption
  and the questions under `#{@faq_heading}` become collapsible entries.
  """
  @spec feature_layout(String.t()) :: feature_layout()
  def feature_layout(html) do
    {hero, html} =
      case Regex.run(@image, html) do
        [match, src, width, height, alt] ->
          {%{src: src, width: width, height: height, alt: alt}, String.replace(html, match, "", global: false)}

        nil ->
          {nil, html}
      end

    [intro | parts] = String.split(html, ~r/(?=<h2>)/)

    sections =
      for part <- parts do
        [_, title, body] = Regex.run(~r/\A<h2>(.*?)<\/h2>\n?(.*)\z/s, part)
        plain_title = title |> String.replace(~r/<[^>]+>/, "") |> String.trim()
        faq? = plain_title == @faq_heading

        body =
          @image
          |> Regex.replace(body, fn _, src, width, height, alt ->
            ~s(<figure><img src="#{src}" width="#{width}" height="#{height}" loading="lazy" decoding="async" alt="#{alt}" /><figcaption>#{alt}</figcaption></figure>\n)
          end)
          |> steps()
          |> then(&if(faq?, do: faq_details(&1), else: &1))

        %{
          id: slugify(plain_title),
          title: title,
          html: body,
          faq?: faq?,
          band?: body =~ ~s(<tr class="firmowid">),
          wide?: body =~ ~s(class="feature-flow")
        }
      end

    %{hero: hero, intro: String.trim(intro), sections: sections}
  end

  # A table whose first column is "Krok" becomes numbered step cards. When its
  # rows carry screenshots, the cards sit next to the screens, which take turns
  # with the highlighted step (see `.feature-flow` in assets/css/landing.css).
  defp steps(html) do
    Regex.replace(
      ~r/<table>\s*<thead>\s*<tr>\s*<th>Krok<\/th>.*?<\/thead>\s*<tbody>(.*?)<\/tbody>\s*<\/table>/s,
      html,
      fn _, rows ->
        rows =
          for [_, row] <- Regex.scan(~r/<tr>(.*?)<\/tr>/s, rows) do
            cells = for [_, cell] <- Regex.scan(~r/<td>(.*?)<\/td>/s, row), do: cell
            Enum.split_with(cells, &String.starts_with?(&1, "<img"))
          end

        items =
          Enum.map_join(rows, fn {_images, [title | details]} ->
            ~s(<li><b>#{title}</b>) <> Enum.map_join(details, &~s(<span>#{&1}</span>)) <> "</li>"
          end)

        case Enum.flat_map(rows, fn {images, _} -> images end) do
          [] ->
            ~s(<ol class="steps">#{items}</ol>)

          images ->
            screens = Enum.map_join(images, &"<figure>#{&1}</figure>")

            ~s(<div class="feature-flow" data-steps="#{length(images)}"><ol class="steps">#{items}</ol>) <>
              ~s(<div class="feature-flow__screens">#{screens}</div></div>)
        end
      end
    )
  end

  defp faq_details(html) do
    html
    |> String.split(~r/(?=<h3>)/)
    |> Enum.map_join(fn
      "<h3>" <> _ = entry ->
        [_, question, answer] = Regex.run(~r/\A<h3>(.*?)<\/h3>\n?(.*)\z/s, entry)
        ~s(<details><summary>#{question}</summary><div>#{String.trim(answer)}</div></details>\n)

      other ->
        other
    end)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace("ł", "l")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp plain_answer(markdown) do
    markdown
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    # Empty paragraphs, images and single-line italic captions.
    |> Enum.reject(&(&1 =~ ~r/\A(?:\z|!\[|\*[^*\n]+\*\z)/u))
    |> Enum.join(" ")
    |> then(&Regex.replace(~r/\[([^\]]+)\]\([^)]+\)/u, &1, "\\1"))
    |> String.replace("**", "")
  end
end
