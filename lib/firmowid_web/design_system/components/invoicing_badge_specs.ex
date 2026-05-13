defmodule FirmowidWeb.DesignSystem.Components.InvoicingBadgeSpecs do
  @moduledoc """
  Explicit bank badge variant data for `InvoicingBadges`.

  The specs keep the current exported-asset rendering 1:1 while allowing the
  component implementation to share the surrounding frame and logo rendering.
  """

  use FirmowidWeb, :html

  @banks [
    "Alior Bank",
    "Millenium",
    "Pekao SA",
    "Paribas",
    "ING",
    "mBank",
    "mBank (firma)",
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
    "PayPal",
    "Paysera",
    "Revolut",
    "Skrill",
    "Soldo",
    "Stripe",
    "Vivid",
    "Wise"
  ]

  default_abs_img = "absolute inset-0 block size-full max-w-none"
  cover_abs_img = "pointer-events-none absolute inset-0 size-full max-w-none object-cover"
  hidden_crop = "pointer-events-none absolute inset-0 overflow-hidden"

  mini_wide_root_class =
    "content-stretch flex h-[24px] items-center justify-center px-[10px] py-[4px] relative rounded-[2px] w-[36px]"

  div = fn class, children -> %{tag: :div, attrs: [class: class], children: children} end
  img = fn asset, class -> %{tag: :img, attrs: [alt: "", class: class], asset: asset} end

  plain_logo = fn outer_class, asset ->
    div.(outer_class, [img.(asset, default_abs_img)])
  end

  plain_logo_with_img_class = fn outer_class, asset, image_class ->
    div.(outer_class, [img.(asset, image_class)])
  end

  wrapped_logo = fn outer_class, inner_class, asset ->
    div.(outer_class, [div.(inner_class, [img.(asset, default_abs_img)])])
  end

  overflow_logo = fn outer_class, asset, image_class ->
    div.(outer_class, [div.(hidden_crop, [img.(asset, image_class)])])
  end

  spec = fn bg, indicator, logo ->
    %{bg: bg, indicator: indicator, logo: logo}
  end

  custom_root_spec = fn bg, indicator, root_class, logo ->
    %{bg: bg, indicator: indicator, root: root_class, logo: logo}
  end

  @bank_specs %{
    {"Alior Bank", "full"} =>
      spec.(
        "bg-[#6b113d]",
        "vector.svg",
        plain_logo.("relative size-[26px] shrink-0", "alr_wa_1.svg")
      ),
    {"Alior Bank", "mini"} => spec.("bg-[#6b113d]", nil, plain_logo.("relative size-[16px] shrink-0", "alr_wa_2.svg")),
    {"Millenium", "full"} =>
      spec.(
        "bg-[#c71052]",
        "vector.svg",
        wrapped_logo.(
          "relative flex size-[26px] shrink-0 flex-col content-stretch items-center justify-center py-px",
          "relative h-[23.37px] w-[26px] shrink-0",
          "mil_wa_1.svg"
        )
      ),
    {"Millenium", "mini"} =>
      spec.(
        "bg-[#c71052]",
        nil,
        wrapped_logo.(
          "relative flex size-[16px] shrink-0 flex-col content-stretch items-center justify-center py-[0.615px]",
          "relative h-[14.381px] w-[16px] shrink-0",
          "mil_wa_2.svg"
        )
      ),
    {"Pekao SA", "full"} =>
      spec.(
        "bg-[#d71a20]",
        "vector.svg",
        overflow_logo.(
          "relative size-[26px] shrink-0",
          "image4.png",
          "absolute top-[-16.37%] left-[-15.51%] size-[131.28%] max-w-none"
        )
      ),
    {"Pekao SA", "mini"} =>
      spec.(
        "bg-[#d71a20]",
        nil,
        overflow_logo.(
          "relative size-[20px] shrink-0",
          "image4.png",
          "absolute top-[-14.51%] left-[-14.88%] size-[131.28%] max-w-none"
        )
      ),
    {"Paribas", "full"} =>
      spec.(
        "bg-[#019d67]",
        "vector.svg",
        div.("relative size-[26px] shrink-0 overflow-clip", [
          div.("absolute inset-[0_0.01%_0.06%_0] contents", [
            div.("absolute inset-[0_0.01%_0.06%_0]", [img.("layer.svg", default_abs_img)])
          ])
        ])
      ),
    {"Paribas", "mini"} =>
      spec.(
        "bg-[#019d67]",
        nil,
        div.("relative size-[16px] shrink-0 overflow-clip", [
          div.("absolute inset-[0_0.01%_0.06%_0] contents", [
            div.("absolute inset-[0_0.01%_0.06%_0]", [img.("layer1.svg", default_abs_img)])
          ])
        ])
      ),
    {"ING", "full"} =>
      spec.(
        "bg-[#ff6200]",
        "vector.svg",
        div.("relative flex size-[26px] shrink-0 flex-col content-stretch items-start py-[4px]", [
          div.("relative h-[16.753px] w-[26px] shrink-0 overflow-clip", [
            div.("absolute inset-[0_0.14%_0.13%_0.02%] contents", [
              div.("absolute inset-[0_0.14%_0.13%_0.02%]", [img.("g9.svg", default_abs_img)])
            ])
          ])
        ])
      ),
    {"ING", "mini"} =>
      spec.(
        "bg-[#ff6200]",
        nil,
        div.(
          "relative flex size-[20px] shrink-0 flex-col content-stretch items-start py-[3.077px]",
          [
            div.("relative h-[12.887px] w-[20px] shrink-0 overflow-clip", [
              div.("absolute inset-[0_0.14%_0.13%_0.02%] contents", [
                div.("absolute inset-[0_0.14%_0.13%_0.02%]", [img.("g10.svg", default_abs_img)])
              ])
            ])
          ]
        )
      ),
    {"mBank", "full"} =>
      spec.(
        "bg-[#26221e]",
        "vector.svg",
        plain_logo.("relative h-[42px] w-[26px] shrink-0", "mbk_wa_1.svg")
      ),
    {"mBank", "mini"} =>
      spec.(
        "bg-[#26221e]",
        nil,
        plain_logo.("relative h-[24px] w-[14.857px] shrink-0", "mbk_wa_2.svg")
      ),
    {"mBank (firma)", "full"} =>
      spec.(
        "bg-[#26221e]",
        "vector.svg",
        plain_logo.("relative h-[42px] w-[26px] shrink-0", "mbk_wa_3.svg")
      ),
    {"mBank (firma)", "mini"} =>
      spec.(
        "bg-[#26221e]",
        nil,
        plain_logo.("relative h-[24px] w-[14.857px] shrink-0", "mbk_wa_4.svg")
      ),
    {"PKO BP", "full"} =>
      spec.(
        "bg-[#13488e]",
        "vector.svg",
        div.("relative flex size-[26px] shrink-0 content-stretch items-center px-[4px]", [
          div.("relative h-[26px] w-[17.879px] shrink-0 overflow-clip", [
            div.("absolute inset-[0.02%_0.08%_0.05%_0.08%] contents", [
              div.("absolute inset-[0.02%_0.08%_0.05%_0.08%] contents", [
                div.("absolute inset-[0.02%_0.08%_0.05%_0.08%]", [
                  img.("pkobp_pion.svg", default_abs_img)
                ])
              ])
            ])
          ])
        ])
      ),
    {"PKO BP", "mini"} =>
      custom_root_spec.(
        "bg-[#13488e]",
        nil,
        mini_wide_root_class,
        div.(
          "relative flex h-[15px] shrink-0 content-stretch items-center justify-center px-[2.308px]",
          [
            div.("relative h-[15px] w-[10.315px] shrink-0 overflow-clip", [
              div.("absolute inset-[0.02%_0.07%_0.05%_0.08%] contents", [
                div.("absolute inset-[0.02%_0.07%_0.05%_0.08%] contents", [
                  div.("absolute inset-[0.02%_0.07%_0.05%_0.08%]", [
                    img.("pkobp_pion1.svg", default_abs_img)
                  ])
                ])
              ])
            ])
          ]
        )
      ),
    {"Default", "full"} =>
      spec.(
        "bg-[#4e4e4e]",
        "vector.svg",
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 size-[26px]", [
              img.("frame.svg", default_abs_img)
            ])
          ]
        )
      ),
    {"Default", "mini"} =>
      custom_root_spec.(
        "bg-[#4e4e4e]",
        nil,
        mini_wide_root_class,
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 size-[16px]", [
              img.("frame1.svg", default_abs_img)
            ])
          ]
        )
      ),
    {"Citi Bank", "full"} =>
      spec.(
        "bg-[#004888]",
        "vector.svg",
        wrapped_logo.(
          "relative size-[26px] shrink-0 overflow-clip",
          "absolute top-[5.5px] left-0 h-[14.958px] w-[26px]",
          "cd1.svg"
        )
      ),
    {"Citi Bank", "mini"} =>
      custom_root_spec.(
        "bg-[#004888]",
        nil,
        mini_wide_root_class,
        wrapped_logo.(
          "relative size-[16px] shrink-0 overflow-clip",
          "absolute top-[3.38px] left-0 h-[9.205px] w-[16px]",
          "cd2.svg"
        )
      ),
    {"Raiffeisen Bank", "full"} =>
      spec.(
        "bg-[#fff21f]",
        "vector1.svg",
        plain_logo.("relative size-[26px] shrink-0", "logo.svg")
      ),
    {"Raiffeisen Bank", "mini"} => spec.("bg-[#fff21f]", nil, plain_logo.("relative size-[16px] shrink-0", "logo1.svg")),
    {"Santander", "full"} =>
      spec.(
        "bg-[#ec0000]",
        "vector.svg",
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 flex size-[26px] content-stretch items-center", [
              div.("relative h-[24.601px] w-[26.001px] shrink-0", [
                img.("g8.svg", default_abs_img)
              ])
            ])
          ]
        )
      ),
    {"Santander", "mini"} =>
      spec.(
        "bg-[#ec0000]",
        nil,
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 flex size-[16px] content-stretch items-center", [
              div.("relative h-[15.139px] w-[16.001px] shrink-0", [
                img.("g11.svg", default_abs_img)
              ])
            ])
          ]
        )
      ),
    {"Velo Bank", "full"} =>
      spec.(
        "bg-[#00b341]",
        "vector.svg",
        overflow_logo.(
          "relative size-[26px] shrink-0",
          "bank_account_image.png",
          "absolute top-[-58.33%] left-[-58.33%] size-[216.67%] max-w-none"
        )
      ),
    {"Velo Bank", "mini"} =>
      spec.(
        "bg-[#00b341]",
        nil,
        overflow_logo.(
          "relative size-[16px] shrink-0",
          "bank_account_image.png",
          "absolute top-[-58.33%] left-[-58.33%] size-[216.67%] max-w-none"
        )
      ),
    {"Credit Agricole", "full"} =>
      spec.(
        "bg-[#00848c]",
        "vector.svg",
        plain_logo.("relative size-[26px] shrink-0", "frame4242.svg")
      ),
    # Figma labels this mini badge as a duplicate Raiffeisen variant,
    # but the exported asset and colors clearly belong to Credit Agricole.
    {"Credit Agricole", "mini"} =>
      spec.("bg-[#00848c]", nil, plain_logo.("relative size-[16px] shrink-0", "frame4243.svg")),
    {"Aion Bank", "full"} =>
      spec.(
        "bg-[#321267]",
        "vector.svg",
        overflow_logo.(
          "relative h-[24px] w-[35px] shrink-0",
          "image5.png",
          "absolute top-0 left-[-21.77%] h-full w-[274.78%] max-w-none"
        )
      ),
    {"Aion Bank", "mini"} =>
      spec.(
        "bg-[#321267]",
        nil,
        overflow_logo.(
          "relative h-[16px] w-[28px] shrink-0",
          "image5.png",
          "absolute top-0 left-[-9.39%] h-full w-[229.49%] max-w-none"
        )
      ),
    {"Ebury", "full"} =>
      spec.(
        "bg-[#5ac4df]",
        "vector2.svg",
        plain_logo_with_img_class.(
          "relative h-[13.21px] w-[37px] shrink-0",
          "image6.png",
          cover_abs_img
        )
      ),
    {"Ebury", "mini"} =>
      spec.(
        "bg-[#5ac4df]",
        nil,
        plain_logo_with_img_class.(
          "relative h-[8.569px] w-[24px] shrink-0",
          "image6.png",
          cover_abs_img
        )
      ),
    {"Nest Bank", "full"} =>
      spec.(
        "bg-[#16161e]",
        "vector3.svg",
        overflow_logo.(
          "relative size-[26px] shrink-0",
          "image8.png",
          "absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
        )
      ),
    {"Nest Bank", "mini"} =>
      spec.(
        "bg-[#16161e]",
        nil,
        overflow_logo.(
          "relative size-[16px] shrink-0",
          "image8.png",
          "absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
        )
      ),
    {"Airwallex", "full"} =>
      spec.(
        "bg-[#161413]",
        "vector4.svg",
        overflow_logo.(
          "relative h-[19.333px] w-[29px] shrink-0",
          "image9.png",
          "absolute top-0 left-0 h-full w-[486.03%] max-w-none"
        )
      ),
    {"Airwallex", "mini"} =>
      custom_root_spec.(
        "bg-[#161413]",
        nil,
        mini_wide_root_class,
        overflow_logo.(
          "relative h-[12px] w-[18px] shrink-0",
          "image9.png",
          "absolute top-0 left-0 h-full w-[486.03%] max-w-none"
        )
      ),
    {"Erste", "full"} =>
      spec.(
        "bg-[#bae5f6]",
        "vector5.svg",
        plain_logo_with_img_class.(
          "relative h-[10.454px] w-[37px] shrink-0",
          "image10.png",
          cover_abs_img
        )
      ),
    {"Erste", "mini"} =>
      custom_root_spec.(
        "bg-[#bae5f6]",
        nil,
        mini_wide_root_class,
        plain_logo_with_img_class.(
          "relative h-[6.781px] w-[24px] shrink-0",
          "image10.png",
          cover_abs_img
        )
      ),
    {"Finom", "full"} =>
      spec.(
        "bg-[#ff5661]",
        "vector6.svg",
        overflow_logo.(
          "relative h-[8px] w-[39px] shrink-0",
          "image11.png",
          "absolute top-[-116.76%] left-[-5.62%] h-[344.61%] w-[111.76%] max-w-none"
        )
      ),
    {"Finom", "mini"} =>
      spec.(
        "bg-[#ff5661]",
        nil,
        overflow_logo.(
          "relative h-[5.189px] w-[24px] shrink-0",
          "image11.png",
          "absolute top-[-116.76%] left-[-5.62%] h-[344.61%] w-[111.76%] max-w-none"
        )
      ),
    {"HSBC", "full"} =>
      spec.(
        "bg-[#d80110]",
        "vector7.svg",
        plain_logo.("relative h-[15.52px] w-[30.999px] shrink-0", "hsbc11.svg")
      ),
    {"HSBC", "mini"} =>
      custom_root_spec.(
        "bg-[#d80110]",
        nil,
        mini_wide_root_class,
        plain_logo.("relative h-[12px] w-[23.968px] shrink-0", "hsbc12.svg")
      ),
    {"Ikano", "full"} =>
      spec.(
        "bg-[#ee151f]",
        "vector7.svg",
        overflow_logo.(
          "relative h-[20.389px] w-[35px] shrink-0",
          "image12.png",
          "absolute top-[-16.5%] left-[-16.5%] size-[133%] max-w-none"
        )
      ),
    {"Ikano", "mini"} =>
      custom_root_spec.(
        "bg-[#ee151f]",
        nil,
        mini_wide_root_class,
        plain_logo.("relative h-[12px] w-[23.968px] shrink-0", "hsbc12.svg")
      ),
    {"Inteligo", "full"} =>
      spec.(
        "bg-[#b7d5df]",
        "vector8.svg",
        overflow_logo.(
          "relative size-[26px] shrink-0",
          "image13.png",
          "absolute top-[-26.87%] left-[-75.2%] h-[191.67%] w-[255.66%] max-w-none"
        )
      ),
    {"Inteligo", "mini"} =>
      custom_root_spec.(
        "bg-[#b7d5df]",
        nil,
        mini_wide_root_class,
        overflow_logo.(
          "relative size-[16px] shrink-0",
          "image13.png",
          "absolute top-[-26.87%] left-[-75.2%] h-[191.67%] w-[255.66%] max-w-none"
        )
      ),
    {"Lunar", "full"} =>
      spec.(
        "bg-[#00cc39]",
        "vector7.svg",
        overflow_logo.(
          "relative h-[13.344px] w-[36.91px] shrink-0",
          "image14.png",
          "absolute top-[-115.64%] left-[-9.5%] h-[329.15%] w-[119%] max-w-none"
        )
      ),
    {"Lunar", "mini"} =>
      custom_root_spec.(
        "bg-[#00cc39]",
        nil,
        mini_wide_root_class,
        overflow_logo.(
          "relative h-[9.469px] w-[26.19px] shrink-0",
          "image14.png",
          "absolute top-[-115.64%] left-[-9.5%] h-[329.15%] w-[119%] max-w-none"
        )
      ),
    {"Monese", "full"} =>
      spec.(
        "bg-[#0373fd]",
        "vector.svg",
        overflow_logo.(
          "relative size-[26px] shrink-0",
          "image15.png",
          "absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
        )
      ),
    {"Monese", "mini"} =>
      spec.(
        "bg-[#0373fd]",
        nil,
        overflow_logo.(
          "relative size-[16px] shrink-0",
          "image15.png",
          "absolute top-[-26.5%] left-[-26.5%] size-[153%] max-w-none"
        )
      ),
    {"N26", "full"} =>
      spec.(
        "bg-[#36a18b]",
        "vector.svg",
        overflow_logo.(
          "relative h-[19.385px] w-[28px] shrink-0",
          "image16.png",
          "absolute top-[-48.22%] left-[-18%] h-[196.44%] w-[136%] max-w-none"
        )
      ),
    {"N26", "mini"} =>
      spec.(
        "bg-[#36a18b]",
        nil,
        overflow_logo.(
          "relative h-[14.25px] w-[19px] shrink-0",
          "image16.png",
          "absolute top-[-40.67%] left-[-18%] h-[181.33%] w-[136%] max-w-none"
        )
      ),

    # Figma metadata/export labels these two variants as a second Lunar pair,
    # but the visual asset is clearly Neteller.
    {"Neteller", "full"} =>
      spec.(
        "bg-[#3a7d16]",
        "vector7.svg",
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 h-[5.873px] w-[36px]", [
              img.("layer1_copy31.svg", default_abs_img)
            ])
          ]
        )
      ),
    {"Neteller", "mini"} =>
      custom_root_spec.(
        "bg-[#3a7d16]",
        nil,
        mini_wide_root_class,
        div.(
          "relative inline-grid shrink-0 grid-cols-[max-content] grid-rows-[max-content] place-items-start leading-0",
          [
            div.("relative col-1 row-1 mt-0 ml-0 h-[4.568px] w-[28px]", [
              img.("layer1_copy32.svg", default_abs_img)
            ])
          ]
        )
      ),
    {"PayPal", "full"} =>
      spec.(
        "bg-[#d4e8ed]",
        "vector9.svg",
        plain_logo_with_img_class.(
          "relative h-[24.226px] w-[26px] shrink-0",
          "image17.png",
          cover_abs_img
        )
      ),
    {"PayPal", "mini"} =>
      spec.(
        "bg-[#d4e8ed]",
        nil,
        plain_logo_with_img_class.(
          "relative h-[14.908px] w-[16px] shrink-0",
          "image17.png",
          cover_abs_img
        )
      ),
    {"Paysera", "full"} =>
      spec.(
        "bg-[#009]",
        "vector.svg",
        wrapped_logo.(
          "relative size-[26px] shrink-0 overflow-clip",
          "absolute top-0 left-[3px] h-[26px] w-[20.345px] overflow-clip",
          "group1.svg"
        )
      ),
    {"Paysera", "mini"} =>
      spec.(
        "bg-[#009]",
        nil,
        plain_logo.("relative h-[12px] w-[9.39px] shrink-0 overflow-clip", "group.svg")
      ),
    {"Revolut", "full"} =>
      spec.(
        "bg-black",
        "vector.svg",
        plain_logo.("relative size-[24px] shrink-0", "revolut_streamline_simple_icons.svg")
      ),
    {"Revolut", "mini"} =>
      custom_root_spec.(
        "bg-black",
        nil,
        mini_wide_root_class,
        plain_logo.("relative size-[12px] shrink-0", "revolut_streamline_simple_icons1.svg")
      ),

    # Figma exports these visuals as duplicate PKO BP variants,
    # but the exported slice is clearly Skrill.
    {"Skrill", "full"} =>
      spec.(
        "bg-[#862565]",
        "vector.svg",
        plain_logo_with_img_class.(
          "relative h-[12.268px] w-[34px] shrink-0",
          "skrill_logo1.svg",
          cover_abs_img
        )
      ),
    {"Skrill", "mini"} =>
      custom_root_spec.(
        "bg-[#862565]",
        nil,
        mini_wide_root_class,
        plain_logo_with_img_class.(
          "relative h-[7.216px] w-[20px] shrink-0",
          "skrill_logo1.svg",
          cover_abs_img
        )
      ),
    {"Soldo", "full"} =>
      spec.(
        "bg-[#191919]",
        "vector10.svg",
        overflow_logo.(
          "relative h-[21px] w-[36px] shrink-0",
          "image18.png",
          "absolute top-[-38.89%] left-[-3.23%] h-[177.78%] w-[103.23%] max-w-none"
        )
      ),
    {"Soldo", "mini"} =>
      custom_root_spec.(
        "bg-[#191919]",
        nil,
        mini_wide_root_class,
        overflow_logo.(
          "relative h-[14px] w-[24.111px] shrink-0",
          "image18.png",
          "absolute top-[-38.89%] left-[-3.23%] h-[177.78%] w-[103.23%] max-w-none"
        )
      ),
    {"Stripe", "full"} =>
      spec.(
        "bg-[#635bff]",
        "vector.svg",
        wrapped_logo.(
          "relative h-[14.983px] w-[36px] shrink-0 overflow-clip",
          "absolute inset-[0_0_0.02%_0]",
          "group2.svg"
        )
      ),
    {"Stripe", "mini"} =>
      custom_root_spec.(
        "bg-[#635bff]",
        nil,
        mini_wide_root_class,
        wrapped_logo.(
          "relative h-[8.324px] w-[20px] shrink-0 overflow-clip",
          "absolute inset-[0_0_0.02%_0]",
          "group3.svg"
        )
      ),

    # Figma exports these visuals as duplicate Soldo variants,
    # but the exported slices are clearly Vivid.
    {"Vivid", "full"} =>
      spec.(
        "bg-[#6b1ee7]",
        "vector7.svg",
        plain_logo.("relative h-[12.522px] w-[36px] shrink-0", "vivid_money_seeklogo2.svg")
      ),
    {"Vivid", "mini"} =>
      custom_root_spec.(
        "bg-[#6b1ee7]",
        nil,
        mini_wide_root_class,
        plain_logo.("relative h-[6.957px] w-[20px] shrink-0", "vivid_money_seeklogo3.svg")
      ),
    {"Wise", "full"} =>
      spec.(
        "bg-[#9ee56f]",
        "vector11.svg",
        plain_logo.("relative size-[26px] shrink-0", "frame4326.svg")
      ),
    {"Wise", "mini"} =>
      custom_root_spec.(
        "bg-[#9ee56f]",
        nil,
        mini_wide_root_class,
        plain_logo.("relative size-[16px] shrink-0", "frame4327.svg")
      )
  }

  @doc """
  Returns all supported bank badge variants in preview order.
  """
  @spec bank_badge_variants() :: [String.t()]
  def bank_badge_variants, do: @banks

  @doc """
  Returns whether the given bank label is supported as an explicit badge variant.
  """
  @spec supported_bank_variant?(String.t() | nil) :: boolean()
  def supported_bank_variant?(bank) when is_binary(bank), do: bank in @banks
  def supported_bank_variant?(_bank), do: false

  @doc """
  Fetches the internal rendering spec for the given bank badge variant.
  """
  @spec fetch_bank_badge_spec!(String.t(), String.t()) :: map()
  def fetch_bank_badge_spec!(bank, size) do
    case Map.fetch(@bank_specs, {bank, size}) do
      {:ok, spec} ->
        spec

      :error ->
        raise ArgumentError, "Unsupported bank badge variant: #{inspect(bank)} / #{inspect(size)}"
    end
  end
end
