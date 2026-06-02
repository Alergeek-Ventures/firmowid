defmodule Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers do
  @moduledoc """
  Shared helper functions for blob processing changes.
  """

  alias Firmowid.Ash.Invoicing.Services.ReductoApiClient

  @doc """
  Returns the configured Reducto API client module.
  """
  def reducto_client do
    Application.get_env(:firmowid, :reducto_api_client_module, ReductoApiClient)
  end
end
