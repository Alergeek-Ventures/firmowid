defmodule FirmowidWeb.DesignSystem.Components.InvoicingBadges do
  @moduledoc """
  App-owned invoicing badges for the design system.

  The bank badge variants are implemented from the Figma component set at
  node `11701:17853` using the exported asset slices, so the rendered result
  matches the source design instead of approximating the logos in code.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @banks [
    "Alior Bank",
    "Millenium",
    "Pekao SA",
    "Paribas",
    "ING",
    "mBank",
    "PKO BP",
    "Default",
    "Citi Bank",
    "Raiffeisen Bank",
    "Santander",
    "Velo Bank",
    "Credit Agricole",
    "Aion Bank",
    "Ebury",
    "Nest Bank",
    "Airwallex",
    "Erste",
    "Finom",
    "HSBC",
    "Ikano",
    "Inteligo",
    "Lunar",
    "Monese",
    "N26",
    "Neteller",
    "PayPal"
  ]

  @bank_sizes ["full", "mini"]
  @invoice_sources ["document", "ksef", "draft"]
  @invoice_source_sizes ["small", "big"]

  @doc """
  Renders a Figma-faithful bank badge.
  """
  @spec bank_badge(map()) :: Rendered.t()
  attr :bank, :string,
    required: true,
    values: @banks,
    doc: "Institution variant from the Figma bank badge set."

  attr :size, :string,
    default: "full",
    values: @bank_sizes,
    doc: "Figma-aligned size modifier."

  attr :class, :any, default: nil, doc: "Additional classes merged into the badge root."

  attr :rest, :global, include: ~w(aria-label title phx-click phx-hook id data-test-id)

  def bank_badge(assigns), do: bank_badge_variant(assigns)

  defp bank_badge_variant(%{bank: "Alior Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#6b113d]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("alr_wa_1.svg")} />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Alior Bank", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#6b113d]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[16px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("alr_wa_2.svg")} />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Millenium", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#c71052]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative flex size-[26px] shrink-0 flex-col content-stretch items-center justify-center py-px">
        <div class="relative h-[23.37px] w-[26px] shrink-0">
          <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("mil_wa_1.svg")} />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Millenium", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#c71052]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative flex size-[16px] shrink-0 flex-col content-stretch items-center justify-center py-[0.615px]">
        <div class="relative h-[14.381px] w-[16px] shrink-0">
          <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("mil_wa_2.svg")} />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Pekao SA", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#d71a20]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-16.37%] left-[-15.51%] size-[131.28%] max-w-none"
            src={asset("image4.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Pekao SA", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#d71a20]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[20px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-14.51%] left-[-14.88%] size-[131.28%] max-w-none"
            src={asset("image4.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Paribas", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#019d67]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0 overflow-clip">
        <div class="absolute inset-[0_0.01%_0.06%_0] contents">
          <div class="absolute inset-[0_0.01%_0.06%_0]">
            <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("layer.svg")} />
          </div>
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Paribas", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#019d67]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[16px] shrink-0 overflow-clip">
        <div class="absolute inset-[0_0.01%_0.06%_0] contents">
          <div class="absolute inset-[0_0.01%_0.06%_0]">
            <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("layer1.svg")} />
          </div>
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "ING", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#ff6200]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative flex size-[26px] shrink-0 flex-col content-stretch items-start py-[4px]">
        <div class="relative h-[16.753px] w-[26px] shrink-0 overflow-clip">
          <div class="absolute inset-[0_0.14%_0.13%_0.02%] contents">
            <div class="absolute inset-[0_0.14%_0.13%_0.02%]">
              <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("g9.svg")} />
            </div>
          </div>
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "ING", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#ff6200]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative flex size-[20px] shrink-0 flex-col content-stretch items-start py-[3.077px]">
        <div class="relative h-[12.887px] w-[20px] shrink-0 overflow-clip">
          <div class="absolute inset-[0_0.14%_0.13%_0.02%] contents">
            <div class="absolute inset-[0_0.14%_0.13%_0.02%]">
              <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("g10.svg")} />
            </div>
          </div>
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "mBank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#26221e]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[42px] w-[26px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("mbk_wa_1.svg")} />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "mBank", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#26221e]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative h-[24px] w-[14.857px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("mbk_wa_2.svg")} />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "PKO BP", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#13488e]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative flex size-[26px] shrink-0 content-stretch items-center px-[4px]">
        <div class="relative h-[26px] w-[17.879px] shrink-0 overflow-clip">
          <div class="absolute inset-[0.02%_0.08%_0.05%_0.08%] contents">
            <div class="absolute inset-[0.02%_0.08%_0.05%_0.08%] contents">
              <div class="absolute inset-[0.02%_0.08%_0.05%_0.08%]">
                <img
                  alt=""
                  class="absolute inset-0 block size-full max-w-none"
                  src={asset("pkobp_pion.svg")}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "PKO BP", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#13488e]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative flex h-[15px] shrink-0 content-stretch items-center justify-center px-[2.308px]">
        <div class="relative h-[15px] w-[10.315px] shrink-0 overflow-clip">
          <div class="absolute inset-[0.02%_0.07%_0.05%_0.08%] contents">
            <div class="absolute inset-[0.02%_0.07%_0.05%_0.08%] contents">
              <div class="absolute inset-[0.02%_0.07%_0.05%_0.08%]">
                <img
                  alt=""
                  class="absolute inset-0 block size-full max-w-none"
                  src={asset("pkobp_pion1.svg")}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Default", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#4e4e4e]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 size-[26px]">
          <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("frame.svg")} />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Default", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#4e4e4e]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 size-[16px]">
          <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("frame1.svg")} />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Citi Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#004888]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0 overflow-clip">
        <div class="absolute top-[5.5px] left-0 h-[14.958px] w-[26px]">
          <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("cd1.svg")} />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Raiffeisen Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#fff21f]"
      indicator="vector1.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("logo.svg")} />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Santander", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#ec0000]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 flex size-[26px] content-stretch items-center">
          <div class="relative h-[24.601px] w-[26.001px] shrink-0">
            <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("g8.svg")} />
          </div>
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Santander", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#ec0000]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 flex size-[16px] content-stretch items-center">
          <div class="relative h-[15.139px] w-[16.001px] shrink-0">
            <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("g11.svg")} />
          </div>
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Velo Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#00b341]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-58.33%] left-[-58.33%] size-[216.67%] max-w-none"
            src={asset("bank_account_image.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Credit Agricole", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#00848c]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("frame4242.svg")} />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Aion Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#321267]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[24px] w-[35px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-0 left-[-21.77%] h-full w-[274.78%] max-w-none"
            src={asset("image5.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Aion Bank", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#321267]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative h-[16px] w-[28px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-0 left-[-9.39%] h-full w-[229.49%] max-w-none"
            src={asset("image5.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Ebury", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#5ac4df]"
      indicator="vector2.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[13.21px] w-[37px] shrink-0">
        <img
          alt=""
          class="pointer-events-none absolute inset-0 size-full max-w-none object-cover"
          src={asset("image6.png")}
        />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Ebury", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#5ac4df]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative h-[8.569px] w-[24px] shrink-0">
        <img
          alt=""
          class="pointer-events-none absolute inset-0 size-full max-w-none object-cover"
          src={asset("image6.png")}
        />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Nest Bank", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#16161e]"
      indicator="vector3.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
            src={asset("image8.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Nest Bank", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#16161e]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[16px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
            src={asset("image8.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Airwallex", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#161413]"
      indicator="vector4.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[19.333px] w-[29px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-0 left-0 h-full w-[486.03%] max-w-none"
            src={asset("image9.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Airwallex", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#161413]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[12px] w-[18px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-0 left-0 h-full w-[486.03%] max-w-none"
            src={asset("image9.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Erste", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#bae5f6]"
      indicator="vector5.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[10.454px] w-[37px] shrink-0">
        <img
          alt=""
          class="pointer-events-none absolute inset-0 size-full max-w-none object-cover"
          src={asset("image10.png")}
        />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Erste", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#bae5f6]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[6.781px] w-[24px] shrink-0">
        <img
          alt=""
          class="pointer-events-none absolute inset-0 size-full max-w-none object-cover"
          src={asset("image10.png")}
        />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Finom", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#ff5661]"
      indicator="vector6.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[8px] w-[39px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-116.76%] left-[-5.62%] h-[344.61%] w-[111.76%] max-w-none"
            src={asset("image11.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Finom", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#ff5661]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative h-[5.189px] w-[24px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-116.76%] left-[-5.62%] h-[344.61%] w-[111.76%] max-w-none"
            src={asset("image11.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "HSBC", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#d80110]"
      indicator="vector7.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[15.52px] w-[30.999px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("hsbc11.svg")} />
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "HSBC", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#d80110]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[12px] w-[23.968px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("hsbc12.svg")} />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Ikano", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#ee151f]"
      indicator="vector7.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[20.389px] w-[35px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
            src={asset("image12.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Ikano", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#ee151f]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[12px] w-[23.968px] shrink-0">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset("hsbc12.svg")} />
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Inteligo", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#b7d5df]"
      indicator="vector8.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.87%] left-[-75.2%] h-[191.67%] w-[255.66%] max-w-none"
            src={asset("image13.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Inteligo", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#b7d5df]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[16px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.87%] left-[-75.2%] h-[191.67%] w-[255.66%] max-w-none"
            src={asset("image13.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Lunar", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#00cc39]"
      indicator="vector7.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[13.344px] w-[36.91px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-115.64%] left-[-9.5%] h-[329.15%] w-[119%] max-w-none"
            src={asset("image14.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Lunar", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#00cc39]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[9.469px] w-[26.19px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-115.64%] left-[-9.5%] h-[329.15%] w-[119%] max-w-none"
            src={asset("image14.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Monese", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#0373fd]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
            src={asset("image15.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Monese", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#0373fd]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[16px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
            src={asset("image15.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "N26", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#36a18b]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative h-[19.385px] w-[28px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-48.22%] left-[-18%] h-[196.44%] w-[136%] max-w-none"
            src={asset("image16.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "N26", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#36a18b]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative h-[14.25px] w-[19px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-40.67%] left-[-18%] h-[181.33%] w-[136%] max-w-none"
            src={asset("image16.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  # Figma metadata/export labels these two variants as a second Lunar pair,
  # but the visual asset is clearly Neteller.
  defp bank_badge_variant(%{bank: "Neteller", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#3a7d16]"
      indicator="vector7.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 h-[5.873px] w-[36px]">
          <img
            alt=""
            class="absolute inset-0 block size-full max-w-none"
            src={asset("layer1_copy31.svg")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "Neteller", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell
      bg="bg-[#3a7d16]"
      root_class="content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0">
        <div class="relative col-1 row-1 mt-0 ml-0 h-[4.568px] w-[28px]">
          <img
            alt=""
            class="absolute inset-0 block size-full max-w-none"
            src={asset("layer1_copy32.svg")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "PayPal", size: "full"} = assigns) do
    ~H"""
    <.full_bank_shell
      bg="bg-[#0373fd]"
      indicator="vector.svg"
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      <div class="relative size-[26px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
            src={asset("image15.png")}
          />
        </div>
      </div>
    </.full_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: "PayPal", size: "mini"} = assigns) do
    ~H"""
    <.mini_bank_shell bg="bg-[#0373fd]" bank={@bank} class={@class} rest={@rest}>
      <div class="relative size-[16px] shrink-0">
        <div class="pointer-events-none absolute inset-0 overflow-hidden">
          <img
            alt=""
            class="absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
            src={asset("image15.png")}
          />
        </div>
      </div>
    </.mini_bank_shell>
    """
  end

  defp bank_badge_variant(%{bank: bank, size: size}) do
    raise ArgumentError, "Unsupported bank badge variant: #{inspect(bank)} / #{inspect(size)}"
  end

  @doc """
  Renders an invoice source badge.
  """
  @spec invoice_source_badge(map()) :: Rendered.t()
  attr :source, :string,
    required: true,
    values: @invoice_sources,
    doc: "Visual source variant from the Figma badge set."

  attr :size, :string,
    required: true,
    values: @invoice_source_sizes,
    doc: "Size modifier for compact table and larger header contexts."

  attr :class, :any, default: nil, doc: "Additional classes merged into the badge root."

  attr :rest, :global, include: ~w(aria-label title phx-click phx-hook id data-test-id)

  def invoice_source_badge(assigns) do
    ~H"""
    <div
      class={[
        "relative inline-flex shrink-0 items-center justify-center",
        @size == "small" && "h-6 w-9 rounded-[2.286px] border border-[#dddddd]",
        @size == "big" && "border-grey-400 h-8 w-12 rounded-[3px] border-[1.5px]",
        @size == "small" && @source in ["document", "draft"] && "bg-[#dddddd]",
        @size == "big" && @source in ["document", "draft"] && "bg-grey-300",
        @size == "small" && @source == "ksef" && "bg-[#f5f5f5]",
        @size == "big" && @source == "ksef" && "bg-grey-200",
        @source == "draft" && "border-dotted",
        @class
      ]}
      data-size={@size}
      data-source={@source}
      {@rest}
    >
      <span class="sr-only">{@source}</span>
      <Lucideicons.file_input
        :if={@source in ["document", "draft"]}
        class={invoice_source_icon_styles(@size)}
      />
      <span
        :if={@source == "ksef"}
        class={invoice_source_ksef_styles(@size)}
      >
        <span class="text-[#013066]">KS</span><span class="text-[#e70012]">e</span><span class="text-[#013066]">F</span>
      </span>
    </div>
    """
  end

  defp invoice_source_icon_styles("small"), do: "size-4 text-[#737373]"
  defp invoice_source_icon_styles("big"), do: "text-grey-900 size-5"

  defp invoice_source_ksef_styles("small"), do: "text-[10px] leading-[1.55] font-semibold tracking-tight"

  defp invoice_source_ksef_styles("big"), do: "text-xs leading-[1.4] font-semibold tracking-tight"

  attr :bg, :string, required: true
  attr :indicator, :string, required: true
  attr :bank, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :any, default: %{}
  slot :inner_block, required: true

  defp full_bank_shell(assigns) do
    ~H"""
    <div
      class={[
        "relative flex h-[42px] w-[72px] content-stretch items-center gap-[16px] rounded-[4px] pr-[4px] pl-[8px]",
        @bg,
        @class
      ]}
      data-bank={@bank}
      data-size="full"
      {@rest}
    >
      <span class="sr-only">{@bank}</span>
      {render_slot(@inner_block)}
      <div class="absolute top-[28px] left-[51.5px] h-[10px] w-[16.5px]">
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset(@indicator)} />
      </div>
    </div>
    """
  end

  attr :bg, :string, required: true
  attr :bank, :string, required: true

  attr :root_class, :string,
    default: "content-stretch flex h-[24px] items-center justify-center relative rounded-[2px] w-[36px]"

  attr :class, :any, default: nil
  attr :rest, :any, default: %{}
  slot :inner_block, required: true

  defp mini_bank_shell(assigns) do
    ~H"""
    <div
      class={[@root_class, @bg, @class]}
      data-bank={@bank}
      data-size="mini"
      {@rest}
    >
      <span class="sr-only">{@bank}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp asset(filename), do: "/images/invoicing_badges/#{filename}"
end
