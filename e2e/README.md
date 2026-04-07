# E2E Tests

This directory contains end-to-end tests using Playwright.

## Running Tests

```bash
mix test.e2e
```

### Run with slow motion and visible (for debugging)

```bash
SLOW_MO=500 HEADLESS=false mix test --only e2e e2e/test/
```
