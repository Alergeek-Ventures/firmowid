---
title: "Narzędzia MCP Firmowida: pełna lista"
description: "42 narzędzia serwera MCP Firmowida: faktury i KSeF, przelewy, wynagrodzenia, czas pracy, urlopy i Analiza. Co czyta, co zapisuje i jaka rola jest potrzebna."
published: 2026-11-18
updated: 2026-11-18
category: claude-i-chatgpt
---

Serwer MCP Firmowida udostępnia 42 narzędzia: 21 czyta dane, 21 je zapisuje. Dwa z czytających otwierają widżet, w którym potwierdzasz fakturę albo korektę. Poniżej każde narzędzie z opisem i najniższą rolą, która może go użyć.

## Podstawowe dane serwera

| Cecha | Wartość |
|---|---|
| Adres | `https://firmowid.pl/mcp` |
| Transport | Streamable HTTP |
| Logowanie | OAuth 2.1, kod autoryzacyjny z PKCE (S256), zakres `mcp` |
| Rejestracja klienta | Client ID Metadata Document albo Dynamic Client Registration (`POST /oauth/register`) |
| Typ klienta | publiczny, bez `client_secret` |
| Token dostępu | ważny 1 godzinę |
| Token odświeżania | ważny 30 dni, wymieniany przy każdym użyciu |
| Zakres danych | jedna firma, wybrana na ekranie zgody |
| Karta serwera | `/.well-known/mcp/server-card.json` |
| Opis dla agentów | `/.well-known/agent-skills/firmowid-mcp/SKILL.md` |

Adres zwrotny klienta musi być w HTTPS. Wyjątkiem jest adres lokalny (`localhost`, `127.0.0.1`), więc Cursor i inne narzędzia uruchamiane na komputerze łączą się bez dodatkowej konfiguracji.

## Jak czytać tabele

- **Odczyt** niczego nie zmienia w firmie.
- **Zapis** wykonuje się od razu po wywołaniu. Serwer nie pokazuje przy nim własnego okna potwierdzenia. Czy przed wywołaniem zobaczysz pytanie o zgodę, zależy od Twojego klienta (Claude, ChatGPT, Cursor) i jego ustawień, więc zapis może się wykonać bez dodatkowego potwierdzenia.
- **Odczyt + widżet** otwiera podgląd dokumentu. Fakturę albo korektę wystawia dopiero kliknięcie w tym podglądzie.
- **Rola** to najniższa rola w Firmowidzie, która może użyć narzędzia. Kolejność ról: pracownik, fakturowanie, księgowość, admin.

## Czas pracy, urlopy, profil (11)

| Narzędzie | Typ | Co robi | Rola |
|---|---|---|---|
| `list_sessions` | odczyt | pokazuje Twoje sesje pracy od najnowszych; zawsze tylko własne, także na koncie admina | pracownik |
| `get_current_session` | odczyt | zwraca trwającą sesję, jeśli jakaś jest | pracownik |
| `start_session` | zapis | zaczyna sesję teraz, z opisem i projektem; trwająca sesja zostaje zatrzymana | pracownik |
| `stop_current_session` | zapis | kończy trwającą sesję | pracownik |
| `edit_session` | zapis | zmienia Twoją sesję: opis, czas, projekt, pracę zdalną; sesji z miesiąca ze złożoną ewidencją nie da się zmienić | pracownik |
| `add_sessions` | zapis | dodaje zakończone sesje z przeszłości, wszystkie naraz albo żadną; jedna sesja ma najwyżej 24 godziny i nie może nachodzić na inną | pracownik |
| `list_leave_requests` | odczyt | pokazuje Twoje wnioski o nieobecność | pracownik |
| `create_leave_request` | zapis | składa wniosek o nieobecność z powodem: niedyspozycja, wypoczynek albo inne; data początku nie może być przeszła | pracownik |
| `list_projects` | odczyt | pokazuje projekty, do których jesteś przypisany, aktywne albo zarchiwizowane | pracownik |
| `update_profile` | zapis | zmienia Twój profil: imię i nazwisko, telefon, adresy, numer konta do wypłaty, widoczność daty urodzin | pracownik |
| `get_shared_birthday` | odczyt | zwraca Twoją datę urodzin, jeśli ją udostępniasz | pracownik |

Przez MCP nie ma narzędzi do akceptowania wniosków ani do przeglądania godzin innych osób.

## Faktury i kontrahenci (18)

| Narzędzie | Typ | Co robi | Rola |
|---|---|---|---|
| `list_sales_invoices` | odczyt | wyszukuje faktury sprzedażowe po datach, kwocie, walucie, rodzaju, stanie rozliczenia i terminie; kwota uwzględnia korekty | fakturowanie |
| `list_cost_invoices` | odczyt | wyszukuje faktury kosztowe, także po źródle: z KSeF albo wgrane ręcznie | fakturowanie |
| `get_sales_invoice` | odczyt | otwiera jedną fakturę: pozycje, stan po korektach, status w KSeF, lista korekt | fakturowanie |
| `list_counterparties` | odczyt | wyszukuje kontrahentów, aktywnych albo zarchiwizowanych | fakturowanie |
| `suggest_sales_invoice_transactions` | odczyt | układa ranking przelewów, które mogły opłacić fakturę sprzedażową | fakturowanie |
| `suggest_cost_invoice_transactions` | odczyt | to samo dla faktury kosztowej | fakturowanie |
| `preview_sales_invoice` | odczyt + widżet | sprawdza dane faktury i otwiera podgląd z potwierdzeniem; służy też do wystawienia zapisanego szkicu | księgowość |
| `preview_sales_invoice_correction` | odczyt + widżet | pokazuje korektę z wartościami przed i po, wymaga potwierdzenia | księgowość |
| `get_next_sales_invoice_number` | odczyt | podaje następny wolny numer dla daty, w formacie miesięcznym albo rocznym, z opcjonalną serią | księgowość |
| `create_sales_invoice_draft` | zapis | zapisuje kompletny szkic bez numeru; działa także bez połączenia z KSeF | księgowość |
| `update_sales_invoice_draft` | zapis | zmienia zapisany szkic | księgowość |
| `update_sales_invoice_internal_note` | zapis | podmienia notatkę wewnętrzną faktury sprzedażowej; notatka nie trafia do KSeF ani do nabywcy | księgowość |
| `update_cost_invoice_internal_note` | zapis | podmienia notatkę wewnętrzną faktury kosztowej | księgowość |
| `link_sales_invoice_counterparty` | zapis | podpina wystawioną fakturę bez kontrahenta do kontrahenta z bazy; dane nabywcy na fakturze zostają | księgowość |
| `connect_sales_invoice_transactions` | zapis | oznacza fakturę sprzedażową jako opłaconą przez powiązanie z przelewami; można łączyć kilka przelewów i kilka faktur | księgowość |
| `connect_cost_invoice_transactions` | zapis | to samo dla faktury kosztowej | księgowość |
| `disconnect_sales_invoice_transactions` | zapis | usuwa błędne powiązanie; faktura i przelew zostają | księgowość |
| `disconnect_cost_invoice_transactions` | zapis | to samo dla faktury kosztowej | księgowość |

Najważniejsze zasady przy fakturach:

- Nabywcą musi być firma z NIP albo jego zagranicznym odpowiednikiem. Faktury dla osób prywatnych wystawia się w aplikacji, a istniejące można przez MCP czytać.
- Numer PESEL nie występuje w danych wejściowych ani w wynikach.
- Do podglądu potrzebne są: nabywca z adresem, data sprzedaży, termin płatności i pozycje z nazwą, ilością, jednostką, ceną netto i stawką VAT. Sprzedawca, data wystawienia, PLN i przelew na domyślne konto uzupełniają się same.
- Rodzaje faktur dostępne w danych: zwykła i zaliczkowa, krajowa i zagraniczna.
- Faktura odrzucona przez KSeF wraca do szkicu bez numeru. Odrzucona korekta jest usuwana.

## Bank i wynagrodzenia (8)

| Narzędzie | Typ | Co robi | Rola |
|---|---|---|---|
| `list_transactions` | odczyt | wyszukuje przelewy z podłączonych kont po dacie, kwocie, walucie, tekście i stanie: oczekujące, dopasowane, pominięte | fakturowanie |
| `suggest_transaction_invoices` | odczyt | układa ranking nierozliczonych faktur, które może opłacać oczekujący przelew | fakturowanie |
| `update_transaction_internal_note` | zapis | podmienia notatkę wewnętrzną przelewu; danych bankowych nie zmienia | księgowość |
| `restore_transaction_for_matching` | zapis | przywraca pominięty przelew do oczekujących | księgowość |
| `list_monthly_salaries` | odczyt | pokazuje wynagrodzenia miesiąca dla całego zespołu; kwota oczekiwana to stawka razy godziny zaokrąglone w górę | admin |
| `suggest_transaction_salaries` | odczyt | wskazuje, czyje wynagrodzenie opłaca wychodzący przelew w PLN; sprawdza do 6 miesięcy wstecz | admin |
| `connect_transaction_salary` | zapis | rozlicza wynagrodzenie danej osoby za dany miesiąc przelewem | admin |
| `disconnect_transaction_salary` | zapis | zdejmuje przypisanie przelewu do wynagrodzenia | admin |

Pewne dopasowania Firmowid robi sam po każdej synchronizacji banku. „Oczekujące” to więc pozycje, które wymagają decyzji człowieka. Przelew przypięty do wynagrodzenia nie może jednocześnie opłacać faktury.

## KSeF i Analiza (5)

| Narzędzie | Typ | Co robi | Rola |
|---|---|---|---|
| `get_ksef_connection_status` | odczyt | podaje stan połączenia firmy z KSeF: rozłączone, w trakcie łączenia, połączone, wygasłe, oraz metodę: token, certyfikat, certyfikat wygenerowany przez Firmowid; nigdy nie zwraca danych logowania | fakturowanie |
| `list_analysis_entries` | odczyt | zwraca wpisy, z których liczona jest Analiza, za pełne miesiące, najwyżej 12: kontrahent, kwota w PLN, kategoria i przypisania | fakturowanie |
| `list_analysis_tags` | odczyt | pokazuje projekty i własne kategorie dostępne do przypisań | pracownik |
| `set_analysis_entry_category` | zapis | przypisuje wpis do jednej z kategorii: Firma, Podatki albo pominięte w Analizie; zastępuje wcześniejsze przypisania | księgowość |
| `set_analysis_entry_project_tags` | zapis | przypisuje wpis do wybranych projektów i dzieli kwotę po równo; pusta lista usuwa przypisania | księgowość |

KSeF łączy administrator w aplikacji. Serwer nie ma narzędzia do łączenia i nie przyjmuje tokenów, certyfikatów ani haseł. Stan „połączone” nie mówi, kiedy ostatnio pobrano faktury.

## Widżety potwierdzenia

| Widżet | Otwiera go | Co pokazuje |
|---|---|---|
| potwierdzenie faktury | `preview_sales_invoice` | podgląd faktury, wybór numeru lub serii, uwagi, notatka wewnętrzna, potem postęp wysyłki do KSeF |
| potwierdzenie korekty | `preview_sales_invoice_correction` | wartości przed korektą i po niej, wybór numeru, obowiązkowe potwierdzenie |

Widżet jest ważny 15 minut albo krócej, jeśli wcześniej wygaśnie token. Przy każdym kliknięciu Firmowid sprawdza ponownie, czy połączenie nie zostało unieważnione i czy nadal należysz do firmy. Po każdej zmianie widżet przekazuje do rozmowy stan dokumentu, numer faktury i numer KSeF.

## Co może która rola

| Rola | Zakres |
|---|---|
| pracownik | 11 narzędzi czasu pracy, urlopów i profilu oraz lista projektów i kategorii dostępnych w Analizie (`list_analysis_tags`) |
| fakturowanie | dodatkowo odczyt faktur, kontrahentów, przelewów, stanu KSeF, wpisów Analizy i propozycji dopasowań |
| księgowość | dodatkowo podglądy i szkice faktur, notatki, łączenie i rozłączanie płatności, przywracanie przelewów, przypisania w Analizie |
| admin | dodatkowo cztery narzędzia wynagrodzeń |

Narzędzia, których Twoja rola nie może użyć, zwracają odmowę. Uprawnienia sprawdzane są przy każdym wywołaniu.

## Czego na liście nie ma

- Wystawiania faktur dla osób prywatnych.
- Tworzenia i edycji kontrahentów oraz projektów.
- Akceptowania wniosków o nieobecność i ewidencji godzin.
- Delegacji, umów i dokumentów pracowniczych.
- Łączenia banku i KSeF oraz uruchamiania synchronizacji.
- Zatwierdzania kategorii kosztów kontrahenta i tworzenia nowych kategorii w Analizie.

Te rzeczy robi się w aplikacji.

## Zobacz też

- [Firmowid w Claude i ChatGPT](/funkcje/claude-chatgpt-mcp)
- [KSeF, bank, czas projektów i ChatGPT w jednym programie](/poradnik/faktury-ksef-chatgpt-claude-mcp)
