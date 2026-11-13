defmodule FirmowidWeb.Landing.Utilities.GuideMarkdownTest do
  use ExUnit.Case, async: true

  alias FirmowidWeb.Landing.Utilities.GuideMarkdown

  describe "mark_firmowid_rows/1" do
    test "marks a row whose first cell is Firmowid, also in bold" do
      html = "<tr>\n<td>Firmowid</td></tr><tr>\n<td><strong>Firmowid Darmowy</strong></td></tr>"
      marked = GuideMarkdown.mark_firmowid_rows(html)

      assert marked =~ ~s(<tr class="firmowid">\n<td>Firmowid</td>)
      assert marked =~ ~s(<tr class="firmowid">\n<td><strong>Firmowid Darmowy)
    end

    test "leaves other rows and Firmowid in later cells alone" do
      html = "<tr><td>Fakturownia</td><td>Firmowid</td></tr>"

      assert GuideMarkdown.mark_firmowid_rows(html) == html
    end
  end

  describe "split_for_signup/1" do
    test "splits before the second section" do
      html = "<p>Lead</p><h2>One</h2><p>a</p><h2>Two</h2><p>b</p><h2>Three</h2>"

      assert GuideMarkdown.split_for_signup(html) == %{
               before_signup: "<p>Lead</p><h2>One</h2><p>a</p>",
               after_signup: "<h2>Two</h2><p>b</p><h2>Three</h2>"
             }
    end

    test "does not split when only the sources follow" do
      html = "<p>Lead</p><h2>One</h2><p>a</p><h2>Źródła</h2><ul><li>MF</li></ul>"

      assert GuideMarkdown.split_for_signup(html) == %{before_signup: html, after_signup: ""}
    end

    test "keeps a body with one section whole" do
      html = "<p>Lead</p><h2>Only</h2><p>a</p>"

      assert GuideMarkdown.split_for_signup(html) == %{before_signup: html, after_signup: ""}
    end
  end

  describe "faq/1" do
    test "reads each question and its plain answer" do
      markdown = """
      ## Wstęp

      Tekst.

      ## Najczęstsze pytania

      ![Ilustracja](/images/guides/x.webp)
      *Podpis grafiki.*

      ### Czy można?

      **Tak.** Zobacz [cennik](/cennik).

      ### Co dalej?

      Pierwszy akapit.

      Drugi akapit.

      ## Źródła

      - źródło
      """

      assert GuideMarkdown.faq(markdown) == [
               %{question: "Czy można?", answer: "Tak. Zobacz cennik."},
               %{question: "Co dalej?", answer: "Pierwszy akapit. Drugi akapit."}
             ]
    end

    test "keeps list items in an answer" do
      markdown = "## Najczęstsze pytania\n\n### Co jest w planie?\n\n* faktury\n* bank\n"

      assert [%{answer: "* faktury\n* bank"}] = GuideMarkdown.faq(markdown)
    end

    test "returns nothing without a questions section" do
      assert GuideMarkdown.faq("## Wstęp\n\nTekst.\n") == []
    end
  end
end
