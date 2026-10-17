import { test } from '@e2e-dev/web';
import { expect } from 'e2e';

// Fixed, otherwise unused NIP: the shared KSeF test environment holds thousands of invoices
// for popular sample NIPs, which the first fetch would import.
const newCompany = {
  nip: '6970016329',
  name: 'E2E Nowa Firma sp. z o.o.',
};

test('Bytecraft invoices a new company that signs up and receives it from KSeF', { session: 'kira', timeout: 900_000 }, async ({ app, screen, browser, agent }) => {
  // Bytecraft issues a sales invoice to the new company and sends it to the KSeF test environment.
  await app.open('/sprzedazowe');
  await screen.getByRole('button', 'Wprowadź ręcznie').tap();
  await screen.getByRole('textbox', 'NIP klienta').fill(newCompany.nip);
  await screen.getByRole('textbox', 'Nazwa firmy').fill(newCompany.name);
  await screen.getByPlaceholder('Adres').fill('ul. Warmińska 18/4, 80-857 Gdańsk');
  await screen.getByRole('dialog').getByRole('combobox').selectOption('Polska');
  await screen.getByRole('button', 'Kontynuuj').tap();
  await expect(screen.getByRole('heading', 'Sprzedawane towary/usługi')).toBeVisible();

  await screen.getByRole('textbox', 'Wprowadź nazwę').fill('Usługi programistyczne');
  await screen.getByRole('spinbutton', '0').fill('1');
  await screen.getByRole('spinbutton', '0,00').fill('1000');
  await screen.getByRole('button', 'Dalej').tap();
  await expect(screen.getByRole('heading', 'Termin i forma płatności')).toBeVisible();

  await screen.getByRole('button', 'dzisiaj').tap();
  await screen.getByRole('button', '7 dni').tap();
  await screen.getByRole('button', 'Dalej').tap();
  await expect(screen.getByRole('heading', 'Podgląd faktury')).toBeVisible();

  await expect(screen.getByRole('row', '1. Usługi programistyczne 1 szt. 1000,00 23% 1000,00 1230,00')).toBeVisible();
  await expect(screen.getByText('1230,00 zł')).toBeVisible();

  // TODO: once sales invoices sync from KSeF into Firmowid, the suggested number already accounts for
  // invoices sent by earlier runs; drop the custom number and let the agent issue the next invoice.
  const invoiceNumber = `E2E/${Date.now()}`;
  await screen.getByRole('textbox', 'Numer faktury').fill(invoiceNumber);
  await screen.getByRole('button', 'Zapisz i wyślij do KSeF').tap();
  // The heading switches once KSeF assigns its number.
  await expect(screen.getByRole('heading', 'Faktura wysłana do KSeF')).toBeVisible({ timeout: 90_000 });

  await screen.getByRole('button', 'kira@bytecraft.collective').tap();
  await screen.getByRole('button', 'Wyloguj się').tap();

  // The new company signs up.
  await app.open('/zarejestruj');
  await screen.getByLabel('Email').fill(`e2e+${Date.now()}@nowafirma.example`);
  await screen.getByLabel('Hasło').fill('kolejka123456');
  await screen.getByRole('button', 'Stwórz konto').tap();

  await expect(browser).toHaveURL('/organizacja');
  await screen.getByPlaceholder('Identyfikator (NIP)').fill(newCompany.nip);
  await screen.getByPlaceholder('Nazwa organizacji').fill(newCompany.name);
  await screen.getByPlaceholder('Ulica').fill('Warmińska');
  await screen.getByPlaceholder('/').fill('18/4');
  await screen.getByPlaceholder('Kod pocztowy').fill('80-857');
  await screen.getByPlaceholder('Miasto').fill('Gdańsk');
  await screen.getByRole('button', 'Utwórz organizację').tap();
  await expect(browser).toHaveURL('/fakturowanie');

  // It gets a KSeF token from the test environment's taxpayer app and connects Firmowid.
  await browser.goto('https://ap-test.ksef.mf.gov.pl/web/');
  await agent.act('sign in with the test authentication ("Uwierzytelnienie testowe") as the company with NIP {nip}', {
    params: { nip: newCompany.nip },
  });
  await agent.act('generate a new KSeF token named {name} that can view and issue invoices, and show its value', {
    params: { name: 'Firmowid e2e' },
  });
  const token = await browser.evaluate(
    () => document.body.innerText.match(/\d{8}-EC-[0-9A-F-]+\|nip-\d{10}\|[0-9a-f]{64}/)?.[0] ?? null,
  );
  expect(token).toContain(`|nip-${newCompany.nip}|`);

  await app.open('/ustawienia/firma');
  await screen.getByRole('tab', 'Token').tap();
  await screen.getByLabel('Wklej token').fill(token!);
  await screen.getByRole('button', 'Połącz z KSeF').tap();
  await expect(screen.getByText('Połączono z KSeF')).toBeVisible({ timeout: 30_000 });

  // KSeF exposes a new invoice to the buyer only after a few minutes, so the first fetch after
  // connecting can miss it; fetch again from the settings until it arrives.
  await expect
    .poll(
      async () => {
        await app.open('/ustawienia/firma');
        const fetch = screen.getByRole('button', 'Pobierz faktury z KSeF');
        if (await fetch.isVisible()) {
          await fetch.tap();
          await expect(screen.getByRole('button', 'Trwa pobieranie faktur')).toBeVisible();
        }
        await app.open('/fakturowanie');
        return screen.getByText(invoiceNumber).isVisible();
      },
      { timeout: 480_000, interval: 20_000, message: 'the Bytecraft invoice never arrived from KSeF' },
    )
    .toBe(true);
});
