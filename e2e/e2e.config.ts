import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';
import { openrouter } from '@openrouter/ai-sdk-provider';

export default {
  targets: [{ engine: web(), app: { url: process.env.APP_URL ?? 'http://localhost:15010' } }],
  agents: {
    default: {
      model: openrouter(process.env.E2E_MODEL ?? 'openai/gpt-6-luna'),
      context: 'Firmowid is a Polish invoicing app; the whole UI is in Polish.',
      maxModelCalls: 15,
    },
  },
  credentials: {
    kira: {
      username: 'kira@bytecraft.collective',
      password: process.env.E2E_KIRA_PASSWORD ?? 'kolejka123456',
    },
  },
  secrets: {
    buyer_ksef_token: () => {
      const token = process.env.E2E_SECRET_BUYER_KSEF_TOKEN;
      if (!token) throw new Error('E2E_SECRET_BUYER_KSEF_TOKEN must be a KSeF test token for NIP 6970016329.');
      return token;
    },
  },
} satisfies E2EConfig;
