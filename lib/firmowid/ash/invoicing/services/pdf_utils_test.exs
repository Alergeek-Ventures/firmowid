defmodule Firmowid.Ash.Invoicing.Services.PdfUtilsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.Services.PdfUtils

  @xsl """
  <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="text" encoding="UTF-8"/>
    <xsl:template match="/"><xsl:value-of select="root"/></xsl:template>
  </xsl:stylesheet>
  """

  @encodings [:utf8, {:utf16, :little}, {:utf16, :big}]

  test "rejects DOCTYPE before transforming XML in each supported Unicode encoding" do
    marker_path = Briefly.create!()
    File.write!(marker_path, "dummy-xml-marker")

    for encoding <- @encodings do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE root [<!ENTITY marker SYSTEM "file://#{marker_path}">]>
      <root>&marker;</root>
      """

      assert {:error, :doctype_not_allowed} =
               PdfUtils.xslt_transform(encode(xml, encoding), @xsl)
    end
  end

  test "rejects a DOCTYPE even without entity declarations" do
    for encoding <- @encodings do
      xml = encode("<?xml version=\"1.0\"?><!DOCTYPE root><root/>", encoding)
      assert {:error, :doctype_not_allowed} = PdfUtils.xslt_transform(xml, @xsl)
    end
  end

  test "preserves valid XML encodings" do
    for encoding <- @encodings do
      xml = encode("<?xml version=\"1.0\"?><root>żółć &amp; text</root>", encoding)
      assert {:ok, "żółć & text"} = PdfUtils.xslt_transform(xml, @xsl)
    end

    xml =
      :unicode.characters_to_binary(
        ~s(<?xml version="1.0" encoding="ISO-8859-1"?><root>café</root>),
        :utf8,
        :latin1
      )

    assert {:ok, "café"} = PdfUtils.xslt_transform(xml, @xsl)
  end

  test "rejects malformed XML before transformation" do
    assert {:error, {:invalid_xml, _location, _reason}} =
             PdfUtils.xslt_transform("<root>", @xsl)
  end

  defp encode(xml, :utf8), do: xml

  defp encode(xml, {:utf16, :little}) do
    <<0xFF, 0xFE>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :little})
  end

  defp encode(xml, {:utf16, :big}) do
    <<0xFE, 0xFF>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :big})
  end
end
