defmodule Firmowid.Delegations.CommandUploadTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Delegations.CommandUpload

  test "keeps an in-limit PDF with a signature dictionary byte-for-byte" do
    path = pdf_file("BT /F1 12 Tf (Signed order) Tj ET", "/Type /Sig /ByteRange [0 1 2 3]")
    original = File.read!(path)

    assert {:ok, ^path} = CommandUpload.prepare(path)
    assert File.read!(path) == original
  end

  test "reduces a 9 MB PDF without changing its decoded page content" do
    content =
      "BT /F1 12 Tf 50 700 Td (Order 12345 - 2026-11-05) Tj ET\n" <>
        String.duplicate(" \n", 4_500_000)

    path = pdf_file(content)
    assert File.stat!(path).size > 9_000_000

    assert {:ok, compressed_path} = CommandUpload.prepare(path)
    assert File.stat!(compressed_path).size <= 8_000_000
    {page_json, 0} = System.cmd("qpdf", ["--json", "--json-key=pages", compressed_path])
    %{"pages" => [%{"contents" => [reference]}]} = Jason.decode!(page_json)
    [object | _generation] = String.split(reference)

    {decoded_content, 0} =
      System.cmd("qpdf", ["--show-object=#{object}", "--filtered-stream-data", compressed_path])

    assert :crypto.hash(:sha256, decoded_content) == :crypto.hash(:sha256, content)
    assert File.read!(path) != File.read!(compressed_path)
  end

  test "does not rewrite oversized signed, incompressible, or broken PDFs" do
    signed = pdf_file(String.duplicate(" \n", 4_500_000), "/Type /Sig /ByteRange [0 1 2 3]")
    original_hash = :crypto.hash(:sha256, File.read!(signed))
    assert {:error, :signed} = CommandUpload.prepare(signed)
    assert :crypto.hash(:sha256, File.read!(signed)) == original_hash

    # A random stream represents already compressed image data: more compression cannot help.
    incompressible = pdf_file(:crypto.strong_rand_bytes(8_100_000))
    assert {:error, :cannot_compress} = CommandUpload.prepare(incompressible)

    {:ok, broken} = Briefly.create(extname: ".pdf")
    File.write!(broken, String.duplicate("not a PDF", 1_000_000))
    assert {:error, :cannot_compress} = CommandUpload.prepare(broken)
  end

  defp pdf_file(content, extra_dictionary \\ "") do
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< #{extra_dictionary} >>"
    ]

    {body, offsets} =
      objects
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.7\n", []}, fn {object, index}, {body, offsets} ->
        {body <> "#{index} 0 obj\n#{object}\nendobj\n", offsets ++ [byte_size(body)]}
      end)

    xref =
      Enum.map_join(offsets, &"#{String.pad_leading(Integer.to_string(&1), 10, "0")} 00000 n \n")

    pdf =
      body <>
        "xref\n0 7\n0000000000 65535 f \n#{xref}trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n#{byte_size(body)}\n%%EOF\n"

    {:ok, path} = Briefly.create(extname: ".pdf")
    File.write!(path, pdf)
    path
  end
end
