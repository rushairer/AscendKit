# AscendKit — Security Model Draft

## 1. Security posture

AscendKit is a security-first release asset tool. It must assume the following are sensitive:

- App Store Connect API credentials
- API key metadata and private keys
- reviewer contact details
- reviewer/demo account credentials
- pre-release screenshots and unreleased marketing assets
- internal metadata drafts
- build and release diagnostics that may embed private paths or internal identifiers

## 2. Security design goals

- never require plaintext secrets in repository config
- keep secret resolution inside deterministic code, not in prompts
- ensure logs and reports are redacted by default
- support local development, CI, and team-shared secret strategies
- allow dry-run operations without access to every production secret
- minimize the amount of secret material exposed to agent layers

## 3. Secret reference model

Configuration should store references, not values.

Example:

```yaml
app_store_connect:
  issuer_id: ASC_ISSUER_ID
  key_id: ASC_KEY_ID
  private_key:
    provider: file
    ref: ~/.ascendkit/secrets/AuthKey_KEYID.p8
```

Alternative providers:
- env
- file reference
- macOS keychain (planned; not accepted by current CLI auth commands)
- future: 1Password CLI, Vault, cloud secret managers

## 4. Initial secret providers

### Env provider
Use environment variables for CI and simple local setups.

### File provider
Use file references outside the repository for local-only setups.

### Keychain provider
Planned local developer experience on macOS. Until it is implemented and verified, use `file` or `env` references.

## 5. Rules

### Never
- commit `.p8` private keys to git
- print private key contents
- include unredacted secret values in logs or JSON output
- expose secret values to AI tools unless absolutely impossible to avoid (and core design should avoid it)

### Always
- redact by default
- separate config from secret material
- document secure setup patterns
- treat screenshot/demo data as potentially sensitive
- maintain `.gitignore` guidance for sensitive local files

## 6. Screenshot sensitivity

Even screenshots can leak:
- email addresses
- phone numbers
- user names
- order/subscription identifiers
- internal URLs
- dev/staging endpoints
- private design concepts

AscendKit should eventually support screenshot-sensitive-content checks or at least structured warnings.

## 7. Audit and diagnostics

Any diagnostics export should:
- redact secrets
- redact credentials
- optionally trim absolute paths
- avoid embedding raw remote payloads when sensitive

## 8. Agent-safety principle

Agent adapters should invoke AscendKit operations, not directly parse or hold secrets. Agents should ideally only receive:
- success/failure
- redacted diagnostics
- structured findings
- plan/apply summaries

## 9. Recommended future docs

- `docs/secrets.md`
- `docs/threat-model.md`
- `docs/security-checklist.md`
- `SECURITY.md`
