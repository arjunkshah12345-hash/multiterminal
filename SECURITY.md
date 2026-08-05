# Security policy

## Supported versions

The latest commit on `main` is the supported version. Multiterminal is currently
distributed as source and local app builds rather than signed release downloads.

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](https://github.com/arjunkshah12345-hash/multiterminal/security/advisories/new).
Do not open a public issue for an undisclosed vulnerability.

Include the affected commit or app build, macOS version, reproduction steps, and any
relevant logs. Remove credentials, tokens, private paths, and other sensitive data before
submitting.

## MCP bridge

The built-in MCP server binds only to `127.0.0.1` and stores its bearer-token configuration
at `~/Library/Application Support/Multiterminal/mcp.json` with owner-only permissions.
Treat that file as a secret: anyone who can read its token can use the local write tools,
including `send_input`, to drive shells running as your user. Rotate the token by removing
the file while Multiterminal is closed, then relaunching the app. Keep the server disabled
or stop the app when you do not need programmatic access.

MCP requests are also checked for localhost origins. This protects browser-based clients
from accidentally forwarding the token to an unrelated origin, but it is not a substitute
for keeping your macOS account and token file secure.

The project will acknowledge valid reports, assess impact, and coordinate a fix or clear
status update. This is a small open-source project, so response times may vary.
