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

  describe "feature_layout/1" do
    test "takes the first image as the hero, the text before the first heading as the introduction" do
      html = """
      <p>Wcześniej robiliśmy to ręcznie.</p>
      <p><img src="/images/guides/funkcje/a.webp" width="1600" height="900" loading="lazy" decoding="async" alt="Lista faktur" /></p>
      <h2>Na co dzień</h2>
      <p>Tekst.</p>
      <p><img src="/images/guides/funkcje/b.webp" width="800" height="600" loading="lazy" decoding="async" alt="Faktura kosztowa" /></p>
      """

      layout = GuideMarkdown.feature_layout(html)

      assert layout.hero == %{
               src: "/images/guides/funkcje/a.webp",
               width: "1600",
               height: "900",
               alt: "Lista faktur"
             }

      assert layout.intro == "<p>Wcześniej robiliśmy to ręcznie.</p>"

      assert [
               %{
                 id: "na-co-dzien",
                 title: "Na co dzień",
                 faq?: false,
                 band?: false,
                 wide?: false,
                 html: body
               }
             ] =
               layout.sections

      assert body =~ "<figcaption>Faktura kosztowa</figcaption>"
    end

    test "turns step tables into cards, questions into collapsible entries and wraps comparisons" do
      html = """
      <p>Wstęp.</p>
      <h2>Jak to działa</h2>
      <table>
      <thead>
      <tr>
      <th>Krok</th>
      <th>Kto</th>
      </tr>
      </thead>
      <tbody>
      <tr>
      <td>Wniosek</td>
      <td>pracownik</td>
      </tr>
      </tbody>
      </table>
      <h2>Porównanie</h2>
      <table><tbody><tr class="firmowid"><td>Firmowid</td></tr></tbody></table>
      <h2>Najczęstsze pytania</h2>
      <h3>Czy można?</h3>
      <p>Tak.</p>
      """

      [steps, comparison, faq] = GuideMarkdown.feature_layout(html).sections

      assert steps.html =~
               ~s(<ol class="steps"><li><b>Wniosek</b><span>pracownik</span></li></ol>)

      assert comparison.band?

      assert comparison.html =~
               ~s(<div class="table-scroll"><table><tbody><tr class="firmowid">)

      assert faq.faq?
      assert faq.html =~ "<details><summary>Czy można?</summary><div><p>Tak.</p></div></details>"
    end
  end
end
