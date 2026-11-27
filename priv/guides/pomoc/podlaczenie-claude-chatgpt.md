---
title: "Jak podłączyć Firmowid do Claude i ChatGPT: krok po kroku"
description: "Dodajesz serwer MCP pod adresem firmowid.pl/mcp, logujesz się kontem Firmowida i na ekranie zgody wybierasz firmę. Co AI zobaczy, a czego nie dostanie."
published: 2026-11-27
updated: 2026-11-27
category: claude-i-chatgpt
---

Firmowid podłączasz do Claude, ChatGPT albo Cursora jednym adresem: `https://firmowid.pl/mcp`. Logujesz się kontem Firmowida i na ekranie zgody wybierasz firmę. Hasła do KSeF ani do banku AI nie dostaje.

**Co trzeba mieć:** konto w Firmowidzie z dostępem do firmy oraz konto w Claude, ChatGPT albo innym programie, który obsługuje serwery MCP.

## Krok 1. Dodaj serwer MCP w swoim programie

W ustawieniach programu znajdź miejsce na własny serwer MCP. W Claude i ChatGPT nazywa się to konektorem albo aplikacją. Wklej adres:

`https://firmowid.pl/mcp`

Klucza API ani hasła nie wpisujesz. Program sam przekieruje Cię do logowania.

## Krok 2. Zaloguj się kontem Firmowida

Otworzy się strona logowania Firmowida. Jeśli nie masz jeszcze konta albo firmy, najpierw je założysz, a potem wrócisz do zgody.

## Krok 3. Wybierz firmę na ekranie zgody

Ekran ma nagłówek „Połączyć Claude z Firmowidem?” albo z nazwą innego programu. Przy kilku firmach zobaczysz zdanie „Wybierz firmę, w której Claude będzie działać.”. Jedno połączenie obejmuje jedną firmę.

Pod spodem jest lista tego, co program dostanie:

| Napis na ekranie zgody | Rodzaj dostępu |
|---|---|
| „Czyta faktury, kontrahentów, przelewy, wynagrodzenia, czas pracy i urlopy w firmie” | odczyt |
| „Zapisuje czas pracy i urlopy, dodaje notatki i kategorie oraz dopasowuje przelewy do faktur i wynagrodzeń” | zapis |
| „Zmienia Twój profil, w tym numer konta do wypłaty” | zapis |
| „Zapisuje szkice faktur, które trafiają do KSeF dopiero po Twoim potwierdzeniu” | zapis po potwierdzeniu |
| „Nie dostaje danych logowania do KSeF ani do banku” | brak dostępu |

Kliknij **Zezwól**. Przycisk „Odrzuć” przerywa połączenie. Stopka mówi, dokąd wrócisz po decyzji.

## Krok 4. Zadaj pierwsze pytanie

Wróć do rozmowy i sprawdź, czy połączenie działa.

| Polecenie | Co się stanie |
|---|---|
| „Pokaż moje sesje pracy z tego tygodnia” | odczyt, widzisz tylko własne sesje |
| „Które faktury sprzedaży nie mają przelewu?” | odczyt, potrzebna rola z dostępem do finansów |
| „Przygotuj fakturę dla klienta takiego jak w zeszłym miesiącu” | otwiera podgląd, fakturę wystawia dopiero Twoje kliknięcie |

AI widzi tyle, na ile pozwala Twoja rola w firmie. Pracownik zobaczy swój czas, urlopy i projekty, a faktur firmy nie.

## Co warto wiedzieć po podłączeniu

| Sprawa | Jak jest |
|---|---|
| Faktura i korekta | trafiają do KSeF po kliknięciu w oknie podglądu |
| Pozostałe zapisy, na przykład czas pracy | wykonują się od razu po poleceniu |
| Ponowne logowanie | po 30 dniach bez użycia |
| Zmiana albo reset hasła | odwołuje wszystkie połączenia |
| Druga firma | osobne połączenie i osobna zgoda |

W którym planie jest MCP, podaje [cennik](/cennik). Pełną listę 42 narzędzi z rolami znajdziesz na stronie [Narzędzia MCP Firmowida](/pomoc/narzedzia-mcp), a przykłady użycia na stronie [asystent AI w aplikacji, w Claude i w ChatGPT](/funkcje/claude-chatgpt-mcp).
