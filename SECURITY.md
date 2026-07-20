# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in this project, please report it
responsibly by emailing the maintainers directly. Do not open a public issue.

## Credential Safety

**Never commit the following to this repository:**

- Snowflake account identifiers or locator URLs
- Snowflake usernames or passwords
- OAuth tokens or refresh tokens
- Private keys (`.pem`, `.p8`, `.key` files)
- Connection profiles (`connections.toml`, `config.toml`)
- Environment files (`.env`, `.env.*`)
- API keys or secrets of any kind

## Verification

Before pushing, verify no secrets are staged:

```bash
git diff --cached --name-only | xargs grep -l -i "password\|token\|secret\|private_key\|account.*=.*\." || echo "Clean"
```

## .gitignore

The `.gitignore` in this repository excludes common credential files.
Always verify it is in place before your first commit.

## Snowflake Connections

Configure Snowflake connections locally in `~/.snowflake/connections.toml`.
This file is excluded from version control and must never be committed.
