defmodule Firmowid.Blobs.PlanGatesTest do
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers
  import Phoenix.LiveViewTest

  alias Ash.Error.Forbidden
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.Blobs.UploadFingerprint
  alias Firmowid.Scope

  @moduletag :capture_log

  setup do
    previous_extract_result = Application.get_env(:firmowid, :reducto_extract_result)
    previous_reducto_config = Application.get_env(:firmowid, :reducto_api_client)
    {:ok, reducto_base_url} = start_reducto_http_stub()

    # Reducto answers with an error: the documents are created, nothing is read.
    Application.put_env(:firmowid, :reducto_extract_result, {:error, :stub})
    Application.put_env(:firmowid, :reducto_api_client, base_url: reducto_base_url)

    on_exit(fn ->
      restore_env(:reducto_extract_result, previous_extract_result)
      restore_env(:reducto_api_client, previous_reducto_config)
    end)
  end

  describe "documents sent to OCR" do
    test "the Free plan reads ten a month and refuses the eleventh" do
      admin = admin_fixture()
      scope = scope(admin)

      # Last month's document and an attachment that never reaches OCR do not count.
      seed_blob!(admin, :cost_invoice, inserted_at: DateTime.shift(DateTime.utc_now(), day: -62))
      seed_blob!(admin, :none)
      for _ <- 1..9, do: seed_blob!(admin, :cost_invoice)
      assert Blobs.count_ocr_documents(scope: scope) == 9

      # The tenth is read (and fails at the stubbed Reducto, which a month no longer counts).
      assert {:ok, %Blob{}} = upload(scope, "tenth.txt", :cost_invoice)

      seed_blob!(admin, :cost_invoice)
      assert Blobs.count_ocr_documents(scope: scope) == 10

      assert {:error, error} = upload(scope, "eleventh.txt", :cost_invoice)
      assert Blobs.ocr_limit_error?(error)
      assert Exception.message(error) =~ "monthly limit of documents for OCR"
      assert Blobs.count_ocr_documents(scope: scope) == 10

      # An attachment is not read, so the limit does not touch it.
      {:ok, path} = Briefly.create()
      File.write!(path, "attachment")

      assert {:ok, %Blob{}} =
               Blobs.create_blob(path, "text/plain", "attachment.txt", scope: scope)
    end

    test "a file the organization already holds reaches the duplicate handling, not the limit" do
      admin = admin_fixture()
      scope = scope(admin)
      for _ <- 1..10, do: seed_blob!(admin, :cost_invoice)

      {:ok, path} = Briefly.create()
      File.write!(path, "a failed one")

      seed_blob!(admin, :cost_invoice,
        processing_state: :failed,
        blob_checksum: UploadFingerprint.normalized_checksum(path, "text/plain")
      )

      assert {:error, error} =
               Blobs.create_blob_for_processing(
                 path,
                 "text/plain",
                 "again.txt",
                 :cost_invoice,
                 %{},
                 scope: scope
               )

      refute Blobs.ocr_limit_error?(error)
    end

    test "the Company plan has no limit" do
      admin = admin_fixture(%{plan: :firma})
      scope = scope(admin)
      for _ <- 1..10, do: seed_blob!(admin, :cost_invoice)

      assert {:ok, %Blob{}} = upload(scope, "eleventh.txt", :cost_invoice)
    end
  end

  describe "employment contract uploads" do
    test "need a plan with employee contracts, also for an admin" do
      free_admin = admin_fixture()

      assert {:error, %Forbidden{}} =
               upload(scope(free_admin), "contract.pdf", :employment_contract)

      admin = admin_fixture(%{plan: :przedsiebiorca})

      assert {:ok, %Blob{processing_target: :employment_contract}} =
               upload(scope(admin), "contract.pdf", :employment_contract)
    end

    test "the documents page offers the upload only where the plan includes it", %{conn: conn} do
      free_admin = admin_fixture()
      {:ok, view, _html} = conn |> log_in_user(free_admin) |> live(~p"/ustawienia/dokumenty")

      assert has_element?(view, "#profile-documents-plan-locked button[disabled]")
      refute has_element?(view, "input[name=document_upload]")

      admin = admin_fixture(%{plan: :przedsiebiorca})
      {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/ustawienia/dokumenty")

      refute has_element?(view, "#profile-documents-plan-locked")
      assert has_element?(view, "input[name=document_upload]")
    end
  end

  defp scope(user), do: %Scope{actor: user, tenant: user.member.organization_id}

  defp upload(scope, filename, target, content \\ nil) do
    {:ok, path} = Briefly.create()
    File.write!(path, content || "document #{System.unique_integer([:positive])}")

    metadata =
      if target == :employment_contract, do: %{member_id: scope.actor.member.id}, else: %{}

    Blobs.create_blob_for_processing(path, "text/plain", filename, target, metadata, scope: scope)
  end

  defp seed_blob!(user, target, attrs \\ []) do
    Ash.Seed.seed!(
      Blob,
      Map.merge(
        %{
          blob_path: "/test/#{System.unique_integer([:positive])}.pdf",
          blob_checksum: "seeded-#{System.unique_integer([:positive])}",
          original_filename: "seeded.pdf",
          processing_target: target,
          processing_state: :succeeded,
          organization_id: user.member.organization_id
        },
        Map.new(attrs)
      )
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
