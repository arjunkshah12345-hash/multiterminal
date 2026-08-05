# Multiterminal MCP

Multiterminal includes a small MCP server in the native app process. It exposes the same
projects and live PTYs that are visible in the window, so an external app can build on top
of Multiterminal without launching a second terminal manager.

## Connect

Launch Multiterminal. The server listens on:

```text
http://127.0.0.1:17442/mcp
```

The app writes a ready-to-paste configuration here:

```text
~/Library/Application Support/Multiterminal/mcp.json
```

It has the standard `mcpServers` shape:

```json
{
  "mcpServers": {
    "multiterminal": {
      "url": "http://127.0.0.1:17442/mcp",
      "headers": {
        "Authorization": "Bearer <generated-token>"
      }
    }
  }
}
```

The **Multiterminal → Copy MCP Configuration** menu item copies the same block to the
clipboard. Set `MULTITERMINAL_MCP_PORT` before launching if another local service owns the
default port; the generated configuration follows that value.

## Read the workspace

The transport is JSON-RPC 2.0 over `POST /mcp`. A request must include the bearer token.
For example, this lists projects:

```sh
MCP_CONFIG="$HOME/Library/Application Support/Multiterminal/mcp.json"
TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mcpServers"]["multiterminal"]["headers"]["Authorization"])' "$MCP_CONFIG")

curl -s http://127.0.0.1:17442/mcp \
  -H "Authorization: $TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'
```

The server also advertises JSON resources:

| URI | Contents |
| --- | --- |
| `multiterminal://projects` | Every project and its session metadata |
| `multiterminal://projects/<uuid>` | One project and its sessions |
| `multiterminal://sessions/<uuid>` | Session metadata and recent readable output |

## Tools

| Tool | Purpose |
| --- | --- |
| `get_workspace` | Read one complete snapshot for automation clients |
| `list_projects` | Read projects and selection state |
| `list_sessions` | Read live session metadata |
| `read_session_output` | Read the bounded recent output of one session |
| `create_project` | Create a project and its first terminal |
| `rename_project` | Rename a project |
| `set_project_directory` | Change a project’s default directory |
| `select_project` | Switch the visible project |
| `delete_project` | Delete a project; requires `confirm: true` |
| `create_terminal` | Start a login shell in a project; accepts an optional shell path |
| `close_terminal` | Close a session; requires `confirm: true` |
| `move_terminal` | Move a pane inside or between projects |
| `focus_session` | Bring the app forward and focus one pane |
| `send_input` | Write text/control characters to a live PTY |

`send_input` is the powerful part of the API. It writes to the shell as the current macOS
user, so callers should show the target session and command to their users. Use
`{"text":"npm test","enter":true}` to type and submit a command, or omit `enter` to
leave text at the prompt.

## Protocol behavior

- MCP protocol version: `2025-11-25`.
- Transport: stateless Streamable HTTP with JSON responses; there is no remote listener or
  cloud relay.
- The server supports `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`,
  and `resources/read`.
- Notifications receive HTTP `202` with no JSON-RPC response.
- Tool failures are returned as MCP tool results with `isError: true` so clients can show
  the actionable error without losing the request context.
- The output transcript is capped per session and stripped of terminal control sequences.

For the threat model and token handling, read [`SECURITY.md`](../SECURITY.md).
