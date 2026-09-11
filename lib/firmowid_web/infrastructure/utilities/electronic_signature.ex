defmodule FirmowidWeb.Infrastructure.Utilities.ElectronicSignature do
  @moduledoc "Shared links for signing documents electronically."

  @trusted_profile_url "https://podpis.gov.pl/podpisz-dokument-elektronicznie/"

  @doc "Returns the government service used to sign a document with Profil Zaufany."
  @spec trusted_profile_url() :: String.t()
  def trusted_profile_url, do: @trusted_profile_url
end
