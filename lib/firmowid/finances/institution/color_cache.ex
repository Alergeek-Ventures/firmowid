defmodule Firmowid.Finances.Institution.ColorCache do
  @moduledoc """
  Caches derived dominant colors for institution logos.

  Reads stay cheap during requests: they return the cached color, and a
  missing one is extracted in the background. The `:institutions` cache is
  started by the application supervisor.
  """

  @cache_name :institutions
  @dominant_color_expire to_timeout(day: 1)

  @doc """
  Returns the cached dominant RGB color for a logo URL.
  """
  @spec get_dominant_color_rgb(String.t() | nil) :: String.t() | nil
  def get_dominant_color_rgb(nil), do: nil

  def get_dominant_color_rgb(logo_url) do
    {:ok, color_rgb} = Cachex.get(@cache_name, logo_url)
    color_rgb
  end

  @doc """
  Extracts the missing dominant colors of the logo URLs in the background.
  """
  @spec warm_dominant_color_rgbs([String.t() | nil]) :: :ok
  def warm_dominant_color_rgbs(logo_urls) do
    logo_urls
    |> Enum.uniq()
    |> Enum.reject(&(is_nil(&1) or get_dominant_color_rgb(&1)))
    |> Enum.each(fn logo_url -> Task.start(fn -> cache_dominant_color_rgb(logo_url) end) end)
  end

  defp cache_dominant_color_rgb(logo_url) do
    Cachex.fetch(@cache_name, logo_url, fn _key ->
      {:commit, extract_dominant_color_rgb(logo_url), expire: @dominant_color_expire}
    end)
  end

  # Picks the best brand-like dominant RGB color of the logo.
  defp extract_dominant_color_rgb(logo_url) do
    with {:ok, %{body: image_binary}} <- Req.get(logo_url),
         {:ok, image} <- Image.open(image_binary),
         {:ok, palette} <- Image.dominant_color(image, method: :imagequant, top_n: 6) do
      palette
      |> pick_brand_color()
      |> rgb_string()
    else
      _error -> nil
    end
  end

  defp pick_brand_color(palette) when is_list(palette) do
    palette
    |> Enum.filter(&usable_brand_color?/1)
    |> Enum.max_by(&brand_color_score/1, fn -> List.first(palette) end)
  end

  defp usable_brand_color?({red, green, blue}) do
    chroma({red, green, blue}) >= 24 and average_channel({red, green, blue}) in 20..235
  end

  defp brand_color_score({red, green, blue}) do
    chroma({red, green, blue}) + abs(128 - average_channel({red, green, blue})) * 0.2
  end

  defp chroma({red, green, blue}) do
    Enum.max([red, green, blue]) - Enum.min([red, green, blue])
  end

  defp average_channel({red, green, blue}) do
    div(red + green + blue, 3)
  end

  defp rgb_string(nil), do: nil
  defp rgb_string({red, green, blue}), do: "#{red} #{green} #{blue}"
end
