defmodule Firmowid.Core.Services.CompanyRegisterTest do
  use Firmowid.DataCase, async: true

  alias Firmowid.Analysis
  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.Services.CompanyRegister

  @moduletag capture_log: true
  @nip "7740001454"

  test "batches missing NIPs by 30 and caches activity and unknown companies across tenants" do
    nips =
      for prefix <- 100_000_000..100_000_040,
          digit <- 0..9,
          nip = "#{prefix}#{digit}",
          Nip.valid?(nip),
          do: nip

    nips = [@nip | Enum.take(nips, 30)]
    owner = self()

    Req.Test.stub(:nip_api, fn conn ->
      batch = conn.request_path |> String.split("/") |> List.last() |> String.split(",")
      send(owner, {:batch, length(batch)})

      entries =
        Enum.map(batch, fn nip ->
          subjects = if nip == @nip, do: [%{"nip" => nip, "krs" => "0000028860"}], else: []
          %{"subjects" => subjects}
        end)

      Req.Test.json(conn, %{"result" => %{"entries" => entries}})
    end)

    Req.Test.expect(:krs_api, fn conn ->
      assert conn.query_string =~ "rejestr=P"
      Plug.Conn.send_resp(conn, 404, "")
    end)

    Req.Test.expect(:krs_api, fn conn ->
      assert conn.query_string =~ "rejestr=S"

      Req.Test.json(conn, %{
        "odpis" => %{
          "dane" => %{
            "dzial3" => %{
              "przedmiotDzialalnosci" => %{
                "przedmiotPrzewazajacejDzialalnosci" => [
                  %{
                    "kodDzial" => "19",
                    "kodKlasa" => "20",
                    "kodPodklasa" => "Z",
                    "opis" => "Rafinacja"
                  }
                ]
              }
            }
          }
        }
      })
    end)

    assert {:ok, companies} =
             CompanyRegister.fetch(nips, Analysis.classifier_scope(Ash.UUID.generate()))

    assert companies[@nip].pkd == "19.20.Z"
    assert companies[@nip].pkd_name == "Rafinacja"
    assert map_size(companies) == 31
    assert Enum.all?(Map.delete(companies, @nip), fn {_nip, company} -> is_nil(company.pkd) end)
    assert_received {:batch, 30}
    assert_received {:batch, 1}

    Req.Test.stub(:nip_api, fn _conn -> flunk("cached NIPs must not reach MF") end)
    Req.Test.stub(:krs_api, fn _conn -> flunk("cached NIPs must not reach KRS") end)

    assert {:ok, cached} =
             CompanyRegister.fetch(nips, Analysis.classifier_scope(Ash.UUID.generate()))

    assert Map.new(cached, fn {nip, company} -> {nip, company.id} end) ==
             Map.new(companies, fn {nip, company} -> {nip, company.id} end)

    assert cached[@nip].pkd == "19.20.Z"
  end

  test "MF rate limit returns an error without poisoning the cache" do
    Req.Test.stub(:nip_api, &Plug.Conn.send_resp(&1, 429, "WL-191"))
    scope = Analysis.classifier_scope(Ash.UUID.generate())

    assert {:error, "HTTP error: 429"} = CompanyRegister.fetch([@nip], scope)
    assert Core.list_registered_companies!([@nip], scope: scope) == []
  end

  test "KRS failures return an error without caching a missing activity" do
    Req.Test.stub(:nip_api, fn conn ->
      Req.Test.json(conn, %{
        "result" => %{"entries" => [%{"subjects" => [%{"nip" => @nip, "krs" => "0000028860"}]}]}
      })
    end)

    Req.Test.stub(:krs_api, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    scope = Analysis.classifier_scope(Ash.UUID.generate())

    assert {:error, {:krs_http_error, 503}} = CompanyRegister.fetch([@nip], scope)
    assert Core.list_registered_companies!([@nip], scope: scope) == []
  end

  test "MF errors inside a successful batch response are returned without caching" do
    error = %{"code" => "WL-191", "message" => "limit"}

    Req.Test.stub(:nip_api, fn conn ->
      Req.Test.json(conn, %{"result" => %{"entries" => [%{"error" => error}]}})
    end)

    scope = Analysis.classifier_scope(Ash.UUID.generate())
    assert {:error, {:vat_lookup_error, ^error}} = CompanyRegister.fetch([@nip], scope)
    assert Core.list_registered_companies!([@nip], scope: scope) == []
  end
end
