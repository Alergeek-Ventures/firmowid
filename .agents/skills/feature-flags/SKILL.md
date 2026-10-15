---
name: feature-flags
description: Use when the user asks to hide a feature behind a flag, or when adding, checking or removing a feature flag.
---

# Feature flags

- Add a flag only when the user asks for one. New features ship without flags
  by default.
- Flags live in PostHog and only hide things in the interface. A missing or
  disabled flag must never break a page, a request or a job, and domain code
  does not read flags.
- Register the flag in `FirmowidWeb.Infrastructure.Flags` (`@flag_keys`). The
  `FeatureFlags` on-mount hook in the router already evaluates every flag for
  authenticated LiveViews; do not add router or per-route plumbing.
- Check the flag inline where the element is rendered or the event is handled,
  with `flag_enabled?/2` against assigns.
- Development enables every flag. Elsewhere a flag defaults to `false` until
  PostHog enables it, so create it in PostHog before relying on it in
  production.
