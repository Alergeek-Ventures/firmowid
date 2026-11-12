---
title: "Revolut i Wise w programie do faktur z KSeF"
description: "Konto Revolut albo Wise w programie do faktur: połączenie przez Open Banking, faktury w euro w KSeF, biała lista VAT i split payment przy zagranicznym IBAN."
published: 2026-11-12
updated: 2026-11-12
category: bank-i-platnosci
---

GoCardless, przez który [Firmowid](/cennik) łączy się z bankami, ma na liście Revolut i Wise obok PKO BP, Pekao, mBanku i ING, więc konto w euro z Wise podłącza się tak samo jak firmowe konto w polskim banku, przez Open Banking.

| Instytucja | Rodzaj | Połączenie w Firmowidzie |
|---|---|---|
| Revolut | konto wielowalutowe | Open Banking |
| Wise | konto wielowalutowe | Open Banking |
| PayPal | płatności online | Open Banking |
| Stripe | płatności kartą | Open Banking |
| PKO BP | bank | Open Banking |
| mBank | bank | Open Banking |

## Waluty

Faktura może być w jednej z 33 walut. Każda waluta ma swoje domyślne konto: euro na przykład Wise, złote PKO. W planie Darmowym podłącza się jedno konto, tylko do odczytu.

## Faktura w euro w KSeF

Kwoty na fakturze w walucie obcej zostają w tej walucie, ale według art. 106e ust. 11 ustawy o VAT kwotę podatku podaje się także w złotych. Kurs: średni NBP z dnia roboczego przed obowiązkiem podatkowym. Przy np II dla firmy z UE podatku nie ma, więc nie ma czego przeliczać.

## Konto z zagranicznym IBAN

Konta w euro z Wise mają belgijski IBAN, z BE na początku, a takich numerów nie ma w wykazie podatników VAT. Klient z Polski, który płaci na taki rachunek ponad 15 000 zł, nie zaliczy wydatku w koszty, chyba że w 7 dni złoży ZAW-NR. Do faktur z obowiązkowym split paymentem potrzebny jest rachunek VAT, a ten prowadzą banki i SKOK-i.

![Revolut i Wise łączą się z Firmowidem przez Open Banking jak polskie banki, tylko do odczytu. Każda z 33 walut może mieć domyślne konto. Konto Wise w euro ma belgijski IBAN, którego nie ma w wykazie podatników VAT, więc przy płatności powyżej 15 000 zł klient składa ZAW-NR.](/images/guides/revolut-wise-konto-w-programie-do-faktur.webp)

## Źródła

- Art. 31a, art. 106e ust. 11 i art. 108a ustawy o VAT; art. 22p ustawy o PIT; art. 117ba Ordynacji podatkowej (ZAW-NR).
- Lista instytucji GoCardless w aplikacji Firmowid, stan 11.11.2026.
- [Firmowid: cennik](https://firmowid.pl/cennik), dostęp 11.11.2026.
- Faktura w euro dla firmy z UE: [np II i odwrotne obciążenie](/poradnik/faktura-dla-firmy-z-ue-ksef).
