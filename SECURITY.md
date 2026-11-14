# Security Policy

## Reporting a vulnerability

Please report suspected security vulnerabilities privately to **[contact@alergeek.ventures](mailto:contact@alergeek.ventures)** with the subject **“Firmowid security report”**. Do not disclose vulnerability details in public GitHub issues, discussions, or pull requests. The same contact is published in [security.txt](https://firmowid.pl/.well-known/security.txt). You can also report through [GitHub private vulnerability reporting](https://github.com/Alergeek-Ventures/firmowid/security/advisories/new), which only maintainers can see.

Useful reports include:

- a clear description and reproduction steps;
- the potential security impact;
- the affected version, commit, or hosted deployment; and
- any relevant logs, requests, or proof-of-concept code.

Please do not include passwords, access tokens, other secrets, or personal data in a report. We ask reporters to allow coordinated disclosure and to avoid sharing details publicly until we have had a reasonable opportunity to investigate and address the issue.

## Cryptography

Firmowid uses published algorithms from maintained libraries (Erlang/OTP `:crypto` and `:public_key`, argon2_elixir, Cloak, plug_crypto, JOSE) and implements no primitives of its own:

- passwords are hashed with Argon2id;
- stored third-party credentials, such as KSeF and bank tokens, are encrypted with AES-256-GCM (Cloak);
- the session cookie is encrypted with XChaCha20-Poly1305 (plug_crypto);
- tokens are signed with HMAC-SHA256;
- traffic uses TLS 1.2 or newer with HSTS.

Two weaker mechanisms remain because external formats require them:

- **KSeF invoice upload.** The KSeF API requires AES-256-CBC with RSA-OAEP-SHA256 key wrapping. Integrity comes from TLS and from the SHA-256 hashes of the plaintext and ciphertext that KSeF checks.
- **Imported signing keys.** Legacy password-based encryption (PBES1) is accepted only to open an encrypted key file a user uploads. Firmowid then stores the key with AES-256-GCM.

## Testing boundaries

Do not perform destructive testing against production, attempt denial-of-service attacks, use social engineering, or violate anyone’s privacy. Test only accounts and data you own or are explicitly authorized to use.

## Scope and response

Only the current `main` branch and the current hosted deployment are supported. We make no support promise for older versions or third-party forks.

We aim to acknowledge reports within **7 business days**. This is a target, not a guarantee of resolution timing. There is currently no bug bounty.

For ordinary support requests and non-security bugs, please use the project’s regular support or issue channels instead of the security channel.
