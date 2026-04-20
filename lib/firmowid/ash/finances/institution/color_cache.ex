defmodule Firmowid.Ash.Finances.Institution.ColorCache do
  @moduledoc """
  Caches derived dominant colors for institution logos.

  Reads stay cheap during requests: callers can return the cached value
  immediately and schedule a background warm-up when the color is missing.
  """

  @cache_name :institutions
  @dominant_color_expire to_timeout(day: 1)

  @doc """
  Returns the cached dominant RGB color for a logo URL.
  """
  @spec get_dominant_color_rgb(String.t() | nil) :: String.t() | nil
  def get_dominant_color_rgb(nil), do: nil

  def get_dominant_color_rgb(logo_url) do
    with {:ok, _pid} <- ensure_cache_started(),
         {:ok, color_rgb} <- Cachex.get(@cache_name, cache_key(logo_url)) do
      color_rgb
    else
      _error -> nil
    end
  end

  @doc """
  Warms the dominant color cache asynchronously for a single logo URL.
  """
  @spec warm_dominant_color_rgb(String.t() | nil) :: :ok
  def warm_dominant_color_rgb(nil), do: :ok

  def warm_dominant_color_rgb(logo_url) do
    if is_nil(get_dominant_color_rgb(logo_url)) do
      Task.start(fn -> persist_dominant_color_rgb(logo_url) end)
    end

    :ok
  end

  @doc """
  Warms the dominant color cache asynchronously for many logo URLs.
  """
  @spec warm_dominant_color_rgbs([String.t() | nil]) :: :ok
  def warm_dominant_color_rgbs(logo_urls) do
    logo_urls
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&warm_dominant_color_rgb/1)

    :ok
  end

  @doc """
  Extracts and persists a dominant RGB color for a logo URL.
  """
  @spec persist_dominant_color_rgb(String.t()) :: String.t() | nil
  def persist_dominant_color_rgb(logo_url) do
    with {:ok, _pid} <- ensure_cache_started(),
         {:ok, color_rgb} <-
           Cachex.fetch(@cache_name, cache_key(logo_url), fn _key ->
             {:commit, extract_dominant_color_rgb(logo_url), expire: @dominant_color_expire}
           end) do
      color_rgb
    else
      _error -> nil
    end
  end

  @doc """
  Extracts the best brand-like dominant RGB color from a logo URL.
  """
  @spec extract_dominant_color_rgb(String.t()) :: String.t() | nil
  def extract_dominant_color_rgb(logo_url) do
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

  defp ensure_cache_started do
    case Process.whereis(@cache_name) do
      nil ->
        case Cachex.start_link(name: @cache_name) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, _reason} ->
            case Process.whereis(@cache_name) do
              nil -> {:error, :invalid_name}
              pid -> {:ok, pid}
            end
        end

      pid ->
        {:ok, pid}
    end
  end

  defp cache_key(logo_url), do: {:dominant_color_rgb_v3, logo_url}

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
