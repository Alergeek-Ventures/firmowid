defmodule FirmowidWeb.Landing.Utilities.GuideMarkdown do
  @moduledoc """
  Pure steps that turn a guide's Markdown and HTML into what the guide page and
  its structured data need. `FirmowidWeb.Landing.Utilities.Guides` calls them at
  compile time.
  """

  @type faq_entry :: %{question: String.t(), answer: String.t()}
  @type body :: %{before_signup: String.t(), after_signup: String.t()}

  @faq_heading "Najczęstsze pytania"

  @doc """
  Marks comparison table rows that start with Firmowid, so the page can set them apart.
  """
  @spec mark_firmowid_rows(String.t()) :: String.t()
  def mark_firmowid_rows(html) do
    Regex.replace(~r/<tr>(\s*<td>(?:<strong>)?Firmowid)/, html, ~S(<tr class="firmowid">\1))
  end

  @doc """
  Splits the body before its second `h2`, where the page shows a sign-up box, so
  the first section reads uninterrupted. A body with one section has nothing after.
  """
  @spec split_for_signup(String.t()) :: body()
  def split_for_signup(html) do
    case String.split(html, "<h2", parts: 3) do
      [lead, first, rest] ->
        %{before_signup: lead <> "<h2" <> first, after_signup: "<h2" <> rest}

      _ ->
        %{before_signup: html, after_signup: ""}
    end
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
