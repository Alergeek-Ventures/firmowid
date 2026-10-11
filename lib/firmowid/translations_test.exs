defmodule Firmowid.TranslationsTest do
  @moduledoc "Focused checks for exact catalog identities and their mismatch diagnostics."
  use ExUnit.Case, async: true

  alias Firmowid.Translations

  test "matching catalogs still validate translations and placeholders" do
    pot = catalog(~s(msgid "Invoice %{number}"\nmsgstr ""\n))
    po = catalog(~s(msgid "Invoice %{number}"\nmsgstr "Faktura %{number}"\n))

    assert :ok = Translations.validate_catalog(pot, po, "default")

    invalid = catalog(~s(msgid "Invoice %{number}"\nmsgstr "Faktura"\n))

    assert {:error, "placeholder mismatch" <> _} =
             Translations.validate_catalog(pot, invalid, "default")
  end

  test "reports missing and extra identities in deterministic order" do
    pot = catalog(~s(msgid "Zebra"\nmsgstr ""\n\nmsgid "Apple"\nmsgstr ""\n))
    po = catalog(~s(msgid "Old"\nmsgstr "Stare"\n))

    assert {:error, message} = Translations.validate_catalog(pot, po, "default")

    assert message == """
           POT/PO identity mismatch for default
           missing from PO: 2
             domain="default" msgctxt=nil msgid="Apple" msgid_plural=nil
             domain="default" msgctxt=nil msgid="Zebra" msgid_plural=nil
           extra in PO: 1
             domain="default" msgctxt=nil msgid="Old" msgid_plural=nil
           The downloaded PO may be stale; newly added or changed source identities require Accent synchronization and Polish translation before exporting a matching catalog.\
           """
  end

  test "context changes remain separate missing and extra identities" do
    pot = catalog(~s(msgctxt "billing"\nmsgid "Invoice"\nmsgstr ""\n))
    po = catalog(~s(msgctxt "archive"\nmsgid "Invoice"\nmsgstr "Faktura"\n))

    assert {:error, message} = Translations.validate_catalog(pot, po, "default")
    assert message =~ "missing from PO: 1"
    assert message =~ "extra in PO: 1"
    assert message =~ ~s(msgctxt="billing" msgid="Invoice" msgid_plural=nil)
    assert message =~ ~s(msgctxt="archive" msgid="Invoice" msgid_plural=nil)
  end

  test "plural changes remain separate missing and extra identities" do
    pot =
      catalog("""
      msgid "Invoice"
      msgid_plural "Invoices"
      msgstr[0] ""
      msgstr[1] ""
      """)

    po =
      catalog("""
      msgid "Invoice"
      msgid_plural "Old invoices"
      msgstr[0] "Faktura"
      msgstr[1] "Faktury"
      msgstr[2] "Faktur"
      """)

    assert {:error, message} = Translations.validate_catalog(pot, po, "default")
    assert message =~ "missing from PO: 1"
    assert message =~ "extra in PO: 1"
    assert message =~ ~s(msgctxt=nil msgid="Invoice" msgid_plural="Invoices")
    assert message =~ ~s(msgctxt=nil msgid="Invoice" msgid_plural="Old invoices")
  end

  test "bounds examples and escapes catalog text without expanding placeholders" do
    long_msgid = "A %{number}\\n" <> String.duplicate("x", 200)

    entries =
      [long_msgid, "B", "C", "D", "E"]
      |> Enum.map_join("\n", &~s(msgid "#{&1}"\nmsgstr ""\n))

    assert {:error, message} = Translations.validate_catalog(catalog(entries), catalog(""), "default")
    assert message =~ "missing from PO: 5"
    assert message =~ "extra in PO: 0"
    assert message =~ "... 2 more identities omitted"
    assert message =~ ~S(A %{number}\n)
    assert message =~ ~s(msgid="C")
    refute message =~ ~s(msgid="D")
    refute message =~ String.duplicate("x", 200)
  end

  defp catalog(entries) do
    Expo.PO.parse_string!("""
    msgid ""
    msgstr ""
    "Language: pl\\n"
    "Plural-Forms: #{Translations.polish_plural_forms()}\\n"

    #{entries}
    """)
  end
end
