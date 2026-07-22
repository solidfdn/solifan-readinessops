# Security Policy

## Reporting a Vulnerability

Do not open a public GitHub issue for a suspected vulnerability.

Email:

```text
contact@solid-fdn.co.jp
```

Use the subject:

```text
[SECURITY][solifan-readinessops] <short summary>
```

Include, when possible:

- Affected file, object, or workflow
- Reproduction steps
- Expected and observed behavior
- Potential impact
- Suggested mitigation
- Whether any credential or real data may have been exposed

Do not include active secrets in the report. If sensitive evidence must be shared, request a secure transfer method first.

## Scope

Security reports may include:

- Credential exposure
- Snowflake privilege or role issues
- Unintended publication paths
- Proposal-state bypasses
- Injection or unsafe dynamic SQL
- Sensitive-data exposure
- Dependency vulnerabilities
- Streamlit authorization issues
- Audit-history integrity issues

General feature requests and documentation corrections may use normal repository channels.

## Credential Safety

Never commit:

- Snowflake account identifiers or private locator URLs
- Usernames or passwords
- OAuth tokens or refresh tokens
- Private keys
- `connections.toml` or local Snowflake CLI configuration
- `.env` files
- API keys
- Customer assessment data
- Production screenshots containing sensitive identifiers

## Local Verification

Before pushing:

```powershell
git status --short
git diff --cached --check
git diff --cached --name-only
```

Review staged content for terms such as:

```text
password
token
secret
private_key
account
oauth
```

Automated searches are supplemental; they do not replace manual review.

## Snowflake Connections

Configure Snowflake CLI connections locally. Do not commit connection profiles or private account details.

## Demonstration Data

The repository is intended to contain synthetic demonstration data only. If real organizational data is introduced during local testing, it must remain outside Git.
