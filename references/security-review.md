# Security review checklist

Defensive review of the diff. Report what is wrong and how to fix it.

## Secrets
Credentials, tokens, keys or connection strings written into tracked files. Client-side env vars (`NEXT_PUBLIC_*`, `VITE_*`) holding anything that should stay server-side. `.env` files that are not ignored.

## Input and output
- User-controlled data reaching `dangerouslySetInnerHTML`, `innerHTML`, `eval`, `new Function`, or a template compiled at runtime.
- URL or redirect target built from user input without an allowlist.
- SQL or shell command built by string concatenation instead of parameters.
- File path built from user input without normalisation.

## Authorisation
- A new route, API handler or mutation with no auth check, where siblings have one.
- Authorisation decided only in the UI, with no server-side equivalent.
- An identifier taken from the request body where it should come from the session.
- Missing ownership check on a resource fetched by ID.

## Data exposure
- API response returning a whole record where the UI needs a few fields.
- PII or tokens in logs, analytics payloads, or error messages.
- Stack traces or internal errors returned to the client.

## Transport and dependencies
- TLS verification disabled.
- `http://` for anything carrying credentials.
- New dependency added for something small, or a package name close to a well-known one: flag for a human to confirm.

## Rules
Report findings and fixes only. Do not write exploit code or proof-of-concept attacks, even to demonstrate a finding. Describe the risk in plain words.
