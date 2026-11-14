defmodule Firmowid.Invoicing.Services.CounterpartyWebsite do
  @moduledoc """
  Finds the domain of a company counterparty's own website, whose icon stands
  for the company on the counterparty list.

  The company's e-mail domain is taken as it is, unless it is a free mailbox.
  Otherwise a small OpenAI model searches the web and answers only when it can
  tell the site belongs to this company, for example by the tax number on it.
  """

  alias Firmowid.Invoicing.Services.OpenAIStructuredResponse

  # Mailboxes anyone can open: their domain says nothing about the company. The
  # big providers run one per country (gmx.de, hotmail.co.uk), so they match by
  # their first label; a company address rejected by mistake goes to the model.
  @free_mail_providers ~w(
    gmail googlemail yahoo ymail hotmail outlook live msn icloud me mac aol gmx web
    proton protonmail pm yandex mail zoho
  )
  @free_mail_domains ~w(
    wp.pl o2.pl go2.pl tlen.pl onet.pl onet.eu op.pl vp.pl poczta.onet.pl interia.pl
    interia.eu poczta.fm int.pl gazeta.pl buziaczek.pl neostrada.pl t-online.de
    seznam.cz free.fr orange.fr wanadoo.fr libero.it
  )

  # One host label after another, ending with a top-level domain of letters.
  @domain ~r/\A(?=.{4,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

  @response_format %{
    type: "json_schema",
    name: "website",
    strict: true,
    schema: %{
      type: "object",
      properties: %{domain: %{type: ["string", "null"]}, evidence: %{type: "string"}},
      required: ["domain", "evidence"],
      additionalProperties: false
    }
  }

  @instructions """
  You find the official website of a company that appears as a counterparty on an
  invoice. Search the web. Return the bare domain (like example.com) of the website
  that belongs to this exact company: the name must match and the country or tax
  identifier must fit. Never return a social profile, a marketplace, a registry or
  a directory, only the company's own site. If several companies share the name and you cannot
  tell which one this is, or you find no site of its own, or you could not verify
  that the site belongs to this company, return null. A wrong domain is worse than
  null. In evidence, say in one sentence how you know.
  """

  @doc """
  Returns the website domain of the company counterparty, nil when none was
  found, or the error when OpenAI could not be reached.
  """
  @spec find_domain(map()) :: {:ok, String.t() | nil} | {:error, Exception.t()}
  def find_domain(counterparty) do
    case email_domain(counterparty.email) do
      nil -> search(counterparty)
      domain -> {:ok, domain}
    end
  end

  @doc "Tells whether `domain` is a bare host name, such as `example.com`."
  @spec valid_domain?(String.t()) :: boolean()
  def valid_domain?(domain), do: Regex.match?(@domain, domain)

  defp email_domain(email) when is_binary(email) do
    with [_local, domain] <- String.split(email, "@"),
         domain when is_binary(domain) <- normalize(domain),
         false <- free_mail?(domain) do
      domain
    else
      _other -> nil
    end
  end

  defp email_domain(nil), do: nil

  defp free_mail?(domain), do: domain in @free_mail_domains or hd(String.split(domain, ".")) in @free_mail_providers

  # No address: a sole proprietor's is often their home.
  defp search(counterparty) do
    input =
      [
        {"Company name", counterparty.full_name},
        {"Short name", counterparty.display_name},
        {"Country", counterparty.country},
        {"Tax identifier", counterparty.tax_id}
      ]
      |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
      |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)

    answer =
      OpenAIStructuredResponse.request!(@instructions, input, @response_format, web_search: "low")

    {:ok, answer |> Map.fetch!("domain") |> normalize()}
  rescue
    # Returned, not raised: Oban retries the job either way, but in tests, which run
    # jobs inline, a raise would fail every test that saves a company.
    error in OpenaiEx.Error -> {:error, error}
    # An answer cut short by the output limit, which the searches count towards,
    # would be cut short again on every retry; the company stays without a logo.
    Jason.DecodeError -> {:ok, nil}
  end

  # The model may answer with a URL; only a valid host name is kept.
  defp normalize(nil), do: nil

  defp normalize(answer) do
    host =
      answer
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r{\A[a-z][a-z0-9+.-]*://}, "")
      |> String.split(["/", "?", "#", ":"], parts: 2)
      |> hd()
      |> String.replace_prefix("www.", "")

    if valid_domain?(host), do: host
  end
end
