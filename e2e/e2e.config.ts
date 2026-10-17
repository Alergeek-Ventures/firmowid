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
} satisfies E2EConfig;
