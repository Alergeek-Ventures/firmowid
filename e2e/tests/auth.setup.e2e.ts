import { test } from '@e2e-dev/web';
import { expect, credentials } from 'e2e';

test.setup('sign in as kira', { sessions: ['kira'] }, async ({ app, screen, session }) => {
  const kira = credentials.user('kira');

  await app.open('/zaloguj');
  await screen.getByRole('button', 'Odrzuć').tap();
  await screen.getByLabel('Email').fill(kira.username);
  await screen.getByLabel('Hasło').fill(kira.password);
  await screen.getByRole('button', 'Zaloguj się').tap();

  await expect(screen.getByRole('button', kira.username)).toBeVisible();
  await session.save('kira');
});
