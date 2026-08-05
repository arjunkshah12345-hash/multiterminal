import AppKit
import Foundation
import Network

/// A small, local-only MCP Streamable HTTP server for the running Multiterminal app.
///
/// The server deliberately lives inside the app process: MCP clients see the same
/// projects and PTYs that the user sees, rather than a second shadow state. It binds to
/// loopback, requires a generated bearer token, and keeps the write surface explicit in
/// the tool descriptions.
final class MCPServer {

    static let defaultPort: UInt16 = 17_442
    private static let protocolVersion = "2025-11-25"
    private static let outputLimit = 64 * 1024
    private static let maxRequestBytes = 1 * 1024 * 1024
    private static let maxInputBytes = 16 * 1024

    private let store: Store
    private let focusSession: (TerminalSession) -> Void
    private let queue = DispatchQueue(label: "com.multiterminal.mcp", qos: .userInitiated)
    private let port: NWEndpoint.Port
    private let token: String
    private let configurationURL: URL
    private var listener: NWListener?

    init(store: Store, focusSession: @escaping (TerminalSession) -> Void) {
        self.store = store
        self.focusSession = focusSession

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Multiterminal", isDirectory: true)
        self.configurationURL = supportDirectory.appendingPathComponent("mcp.json")
        self.token = Self.loadToken(from: configurationURL) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let configuredPort = ProcessInfo.processInfo.environment["MULTITERMINAL_MCP_PORT"]
            .flatMap(UInt16.init)
            .flatMap { $0 > 1024 ? $0 : nil }
            ?? Self.defaultPort
        self.port = NWEndpoint.Port(rawValue: configuredPort)!
    }

    deinit {
        stop()
    }

    var endpointURL: URL {
        URL(string: "http://127.0.0.1:\(port.rawValue)/mcp")!
    }

    var configurationPath: String { configurationURL.path }

    func start() {
        guard listener == nil else { return }
        writeConfiguration()

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            NSLog("Multiterminal MCP could not start: \(error.localizedDescription)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let self else { return }
                NSLog("Multiterminal MCP listening at http://127.0.0.1:\(self.port.rawValue)/mcp")
            case .failed(let error):
                NSLog("Multiterminal MCP stopped: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Copy a client-ready mcpServers block to the pasteboard from the app menu.
    func copyConfigurationToPasteboard() {
        writeConfiguration()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configurationText, forType: .string)
    }

    // MARK: Configuration

    private var configurationObject: [String: Any] {
        [
            "mcpServers": [
                "multiterminal": [
                    "url": endpointURL.absoluteString,
                    "headers": ["Authorization": "Bearer \(token)"]
                ]
            ]
        ]
    }

    private var configurationText: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: configurationObject,
            options: [.prettyPrinted, .sortedKeys]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func writeConfiguration() {
        let fileManager = FileManager.default
        let directory = configurationURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try Data(configurationText.utf8).write(to: configurationURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
        } catch {
            NSLog("Multiterminal MCP could not write \(configurationURL.path): \(error.localizedDescription)")
        }
    }

    private static func loadToken(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let server = servers["multiterminal"] as? [String: Any],
              let headers = server["headers"] as? [String: Any],
              let authorization = headers["Authorization"] as? String,
              authorization.hasPrefix("Bearer ") else {
            return nil
        }
        let value = String(authorization.dropFirst("Bearer ".count))
        return value.isEmpty ? nil : value
    }

    // MARK: HTTP transport

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("Multiterminal MCP connection failed: \(error.localizedDescription)")
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        var buffer = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let data { buffer.append(data) }

            if let request = Self.parseRequest(buffer) {
                self.handle(request, on: connection)
                return
            }
            if buffer.count > Self.maxRequestBytes || error != nil || isComplete {
                self.respond(status: 400, body: ["error": "Invalid HTTP request"], on: connection)
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        let bytes = Array(data)
        guard let separator = findHeaderEnd(in: bytes) else { return nil }
        guard let headerText = String(bytes: bytes[0..<separator], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0 else { return nil }
        let bodyStart = separator + 4
        guard bytes.count >= bodyStart + contentLength else { return nil }
        let body = Data(bytes[bodyStart..<(bodyStart + contentLength)])
        return HTTPRequest(method: requestParts[0], path: requestParts[1], headers: headers, body: body)
    }

    private static func findHeaderEnd(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4) where bytes[index..<index + 4].elementsEqual([13, 10, 13, 10]) {
            return index
        }
        return nil
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let origin = request.headers["origin"]
        guard request.path == "/mcp" else {
            respond(status: 404, body: ["error": "MCP endpoint is /mcp"], origin: origin, on: connection)
            return
        }
        guard origin.map(Self.isAllowedOrigin) ?? true else {
            respond(status: 403, body: ["error": "Origin is not allowed"], origin: origin, on: connection)
            return
        }
        if request.method.uppercased() == "OPTIONS" {
            respond(status: 204, body: nil, origin: origin, on: connection)
            return
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            respond(
                status: 401,
                body: ["error": "Bearer token required"],
                headers: ["WWW-Authenticate": "Bearer"],
                origin: origin,
                on: connection
            )
            return
        }

        switch request.method.uppercased() {
        case "GET":
            // This server is intentionally stateless and does not open an SSE stream.
            respond(
                status: 405,
                body: ["error": "Use POST /mcp for JSON-RPC messages"],
                headers: ["Allow": "POST, OPTIONS"],
                origin: origin,
                on: connection
            )
        case "POST":
            handlePOST(request, origin: origin, on: connection)
        default:
            respond(status: 405, body: ["error": "Method not allowed"], headers: ["Allow": "POST, OPTIONS"], origin: origin, on: connection)
        }
    }

    private func handlePOST(_ request: HTTPRequest, origin: String?, on connection: NWConnection) {
        guard request.body.count <= Self.maxRequestBytes else {
            respond(status: 413, body: ["error": "Request body is too large"], origin: origin, on: connection)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body),
              let message = object as? [String: Any] else {
            respond(status: 400, body: ["error": "Request body must be a JSON-RPC object"], origin: origin, on: connection)
            return
        }

        guard let response = handleRPC(message) else {
            respond(status: 202, body: nil, origin: origin, on: connection)
            return
        }
        respond(status: 200, body: response, origin: origin, on: connection)
    }

    private func respond(
        status: Int,
        body: Any?,
        headers extraHeaders: [String: String] = [:],
        origin: String? = nil,
        on connection: NWConnection
    ) {
        let bodyData: Data
        if let body {
            bodyData = jsonData(body) ?? Data()
        } else {
            bodyData = Data()
        }

        var headers = extraHeaders
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = String(bodyData.count)
        headers["Connection"] = "close"
        headers["MCP-Protocol-Version"] = Self.protocolVersion
        if let origin, Self.isAllowedOrigin(origin) {
            headers["Access-Control-Allow-Origin"] = origin
            headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, MCP-Protocol-Version, MCP-Session-Id"
            headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
        }

        let reason = Self.reasonPhrase(for: status)
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        var responseData = Data(response.utf8)
        responseData.append(bodyData)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func isAllowedOrigin(_ origin: String) -> Bool {
        if origin == "null" { return true }
        guard let url = URL(string: origin), url.scheme == "http", let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }

    // MARK: JSON-RPC / MCP

    private func handleRPC(_ message: [String: Any]) -> [String: Any]? {
        let id = message["id"]
        guard message["jsonrpc"] as? String == "2.0",
              let method = message["method"] as? String else {
            return rpcError(id: id, code: -32600, message: "Invalid JSON-RPC request")
        }

        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String
            let selected = requested == Self.protocolVersion ? requested! : Self.protocolVersion
            return rpcResult(id: id, result: [
                "protocolVersion": selected,
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false]
                ],
                "serverInfo": ["name": "multiterminal", "version": "1.0.0"],
                "instructions": "Multiterminal exposes local projects and live PTY sessions. send_input writes directly to a shell."
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return rpcResult(id: id, result: [:])
        case "tools/list":
            return rpcResult(id: id, result: ["tools": toolDefinitions()])
        case "resources/list":
            return rpcResult(id: id, result: ["resources": onMain { resourceDefinitions() }])
        case "resources/read":
            guard let uri = params["uri"] as? String else {
                return rpcError(id: id, code: -32602, message: "resources/read requires a uri")
            }
            do {
                let content = try onMain { try resourceContent(uri: uri) }
                return rpcResult(id: id, result: ["contents": [content]])
            } catch let error as MCPError {
                return rpcError(id: id, code: -32602, message: error.message)
            } catch {
                return rpcError(id: id, code: -32602, message: error.localizedDescription)
            }
        case "tools/call":
            guard let name = params["name"] as? String else {
                return rpcError(id: id, code: -32602, message: "tools/call requires a name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = onMain { executeTool(name: name, arguments: arguments) }
            return rpcResult(id: id, result: result)
        default:
            return rpcError(id: id, code: -32601, message: "Unknown method: \(method)")
        }
    }

    private func rpcResult(id: Any?, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func rpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            tool(
                name: "get_workspace",
                description: "Read one complete, automation-friendly snapshot of the selected project, all projects, and live sessions.",
                schema: objectSchema()
            ),
            tool(
                name: "list_projects",
                description: "Read all Multiterminal projects, their folders, session counts, and selection state.",
                schema: objectSchema()
            ),
            tool(
                name: "list_sessions",
                description: "Read live terminal sessions. Pass projectId to scope the result to one project.",
                schema: objectSchema(properties: [
                    "projectId": stringProperty(description: "Project UUID; omitted for all projects.")
                ])
            ),
            tool(
                name: "read_session_output",
                description: "Read the recent readable output captured from one live terminal session.",
                schema: objectSchema(
                    properties: [
                        "sessionId": stringProperty(description: "Terminal session UUID."),
                        "maxChars": integerProperty(description: "Maximum characters to return, capped at 65536.")
                    ],
                    required: ["sessionId"]
                )
            ),
            tool(
                name: "create_project",
                description: "Create a project and start its first terminal. workingDirectory must be an existing local directory.",
                schema: objectSchema(properties: [
                    "name": stringProperty(description: "Optional display name."),
                    "workingDirectory": stringProperty(description: "Optional existing directory; defaults to the home directory.")
                ])
            ),
            tool(
                name: "rename_project",
                description: "Rename an existing project.",
                schema: objectSchema(
                    properties: [
                        "projectId": stringProperty(description: "Project UUID."),
                        "name": stringProperty(description: "New non-empty display name.")
                    ],
                    required: ["projectId", "name"]
                )
            ),
            tool(
                name: "set_project_directory",
                description: "Change the default working directory for a project. Existing sessions are not restarted.",
                schema: objectSchema(
                    properties: [
                        "projectId": stringProperty(description: "Project UUID."),
                        "workingDirectory": stringProperty(description: "Existing local directory.")
                    ],
                    required: ["projectId", "workingDirectory"]
                )
            ),
            tool(
                name: "select_project",
                description: "Switch the visible project in the Multiterminal window.",
                schema: objectSchema(
                    properties: ["projectId": stringProperty(description: "Project UUID.")],
                    required: ["projectId"]
                )
            ),
            tool(
                name: "delete_project",
                description: "Delete a project and terminate every shell in it. This is destructive and requires confirm=true.",
                schema: objectSchema(
                    properties: [
                        "projectId": stringProperty(description: "Project UUID."),
                        "confirm": booleanProperty(description: "Must be true to authorize deletion.")
                    ],
                    required: ["projectId", "confirm"]
                )
            ),
            tool(
                name: "create_terminal",
                description: "Start a new login-shell terminal in a project. The directory must exist.",
                schema: objectSchema(properties: [
                    "projectId": stringProperty(description: "Project UUID; omitted for the selected project."),
                    "workingDirectory": stringProperty(description: "Optional existing directory for this session."),
                    "shell": stringProperty(description: "Optional executable shell path, such as /bin/zsh, /bin/bash, or /opt/homebrew/bin/fish.")
                ])
            ),
            tool(
                name: "close_terminal",
                description: "Terminate and remove a terminal session. This is destructive and requires confirm=true.",
                schema: objectSchema(
                    properties: [
                        "sessionId": stringProperty(description: "Terminal session UUID."),
                        "confirm": booleanProperty(description: "Must be true to authorize closing the session.")
                    ],
                    required: ["sessionId", "confirm"]
                )
            ),
            tool(
                name: "move_terminal",
                description: "Move a terminal left/right within its project with offset, or into another project with projectId.",
                schema: objectSchema(
                    properties: [
                        "sessionId": stringProperty(description: "Terminal session UUID."),
                        "offset": integerProperty(description: "Signed pane movement, usually -1 or 1."),
                        "projectId": stringProperty(description: "Destination project UUID; mutually exclusive with offset.")
                    ],
                    required: ["sessionId"]
                )
            ),
            tool(
                name: "focus_session",
                description: "Select the session's project, bring Multiterminal forward, and focus that exact terminal pane.",
                schema: objectSchema(
                    properties: ["sessionId": stringProperty(description: "Terminal session UUID.")],
                    required: ["sessionId"]
                )
            ),
            tool(
                name: "send_input",
                description: "Write text directly to a live terminal PTY. This can execute shell commands; set enter=true to append a Return key.",
                schema: objectSchema(
                    properties: [
                        "sessionId": stringProperty(description: "Terminal session UUID."),
                        "text": stringProperty(description: "Raw text or control characters to write to the PTY; capped at 16 KiB."),
                        "enter": booleanProperty(description: "Append a Return key after text; defaults to false.")
                    ],
                    required: ["sessionId", "text"]
                )
            )
        ]
    }

    private func tool(name: String, description: String, schema: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema]
    }

    private func objectSchema(
        properties: [String: [String: Any]] = [:],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    private func stringProperty(description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private func integerProperty(description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private func booleanProperty(description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    // MARK: Resources

    private func resourceDefinitions() -> [[String: Any]] {
        var resources: [[String: Any]] = [
            [
                "uri": "multiterminal://projects",
                "name": "Projects",
                "description": "All projects and live session metadata.",
                "mimeType": "application/json"
            ]
        ]
        for project in store.projects {
            resources.append([
                "uri": "multiterminal://projects/\(project.id.uuidString)",
                "name": project.name,
                "description": "Project metadata and session list.",
                "mimeType": "application/json"
            ])
            for session in project.sessions {
                resources.append([
                    "uri": "multiterminal://sessions/\(session.id.uuidString)",
                    "name": session.title,
                    "description": "Session metadata and recent terminal output.",
                    "mimeType": "application/json"
                ])
            }
        }
        return resources
    }

    private func resourceContent(uri: String) throws -> [String: Any] {
        guard let url = URL(string: uri), url.scheme == "multiterminal", let host = url.host else {
            throw MCPError("Unsupported resource URI")
        }

        let value: Any
        switch host {
        case "projects" where url.path == "":
            value = projectsSnapshot()
        case "projects":
            guard let id = UUID(uuidString: url.lastPathComponent), let project = project(id: id) else {
                throw MCPError("Project not found")
            }
            value = projectSnapshot(project)
        case "sessions":
            guard let id = UUID(uuidString: url.lastPathComponent), let location = session(id: id) else {
                throw MCPError("Session not found")
            }
            value = sessionSnapshot(location.session, project: location.project)
        default:
            throw MCPError("Unsupported resource URI")
        }

        return [
            "uri": uri,
            "mimeType": "application/json",
            "text": jsonString(value)
        ]
    }

    // MARK: Tools

    private struct SessionLocation {
        let project: Project
        let session: TerminalSession
    }

    private struct MCPError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func executeTool(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            let value: Any
            switch name {
            case "get_workspace":
                value = workspaceSnapshot()
            case "list_projects":
                value = projectsSnapshot()
            case "list_sessions":
                value = try sessionsSnapshot(arguments: arguments)
            case "read_session_output":
                value = try readOutput(arguments: arguments)
            case "create_project":
                value = try createProject(arguments: arguments)
            case "rename_project":
                value = try renameProject(arguments: arguments)
            case "set_project_directory":
                value = try setProjectDirectory(arguments: arguments)
            case "select_project":
                value = try selectProject(arguments: arguments)
            case "delete_project":
                value = try deleteProject(arguments: arguments)
            case "create_terminal":
                value = try createTerminal(arguments: arguments)
            case "close_terminal":
                value = try closeTerminal(arguments: arguments)
            case "move_terminal":
                value = try moveTerminal(arguments: arguments)
            case "focus_session":
                value = try focus(arguments: arguments)
            case "send_input":
                value = try sendInput(arguments: arguments)
            default:
                throw MCPError("Unknown tool: \(name)")
            }
            return toolResult(value)
        } catch let error as MCPError {
            return toolResult(["error": error.message], isError: true)
        } catch {
            return toolResult(["error": error.localizedDescription], isError: true)
        }
    }

    private func projectsSnapshot() -> [[String: Any]] {
        store.projects.map(projectSnapshot)
    }

    private func workspaceSnapshot() -> [String: Any] {
        var result: [String: Any] = [
            "projectCount": store.projects.count,
            "sessionCount": store.projects.reduce(0) { $0 + $1.sessions.count },
            "projects": projectsSnapshot()
        ]
        if let selected = store.selectedProject {
            result["selectedProjectId"] = selected.id.uuidString
            result["selectedProject"] = projectSnapshot(selected)
        }
        return result
    }

    private func projectSnapshot(_ project: Project) -> [String: Any] {
        [
            "id": project.id.uuidString,
            "name": project.name,
            "workingDirectory": project.workingDirectory,
            "sessionCount": project.sessions.count,
            "selected": store.selectedProject === project,
            "sessions": project.sessions.map { sessionSnapshot($0, project: project) }
        ]
    }

    private func sessionsSnapshot(arguments: [String: Any]) throws -> [[String: Any]] {
        let projects: [Project]
        if let rawID = arguments["projectId"] as? String {
            guard let project = project(id: try uuid(rawID, label: "projectId")) else {
                throw MCPError("Project not found")
            }
            projects = [project]
        } else {
            projects = store.projects
        }
        return projects.flatMap { project in
            project.sessions.map { sessionSnapshot($0, project: project) }
        }
    }

    private func sessionSnapshot(_ session: TerminalSession, project: Project) -> [String: Any] {
        [
            "id": session.id.uuidString,
            "projectId": project.id.uuidString,
            "projectName": project.name,
            "title": session.title,
            "workingDirectory": session.workingDirectory ?? project.workingDirectory,
            "alive": session.isAlive,
            "outputResource": "multiterminal://sessions/\(session.id.uuidString)"
        ]
    }

    private func readOutput(arguments: [String: Any]) throws -> [String: Any] {
        let session = try requireSession(arguments)
        let limit = min(max(integer(arguments["maxChars"]) ?? 16 * 1024, 1), Self.outputLimit)
        return [
            "sessionId": session.id.uuidString,
            "output": session.recentOutput(limit: limit),
            "alive": session.isAlive
        ]
    }

    private func createProject(arguments: [String: Any]) throws -> [String: Any] {
        let name = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty { throw MCPError("name must not be empty") }
        let directory = try normalizedDirectory(arguments["workingDirectory"] as? String ?? NSHomeDirectory())
        let project = store.addProject(name: name, workingDirectory: directory)
        return projectSnapshot(project)
    }

    private func renameProject(arguments: [String: Any]) throws -> [String: Any] {
        let project = try requireProject(arguments)
        let name = try requiredString(arguments, key: "name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPError("name must not be empty") }
        guard let index = store.projects.firstIndex(where: { $0 === project }) else { throw MCPError("Project not found") }
        store.renameProject(at: index, to: name)
        return projectSnapshot(project)
    }

    private func setProjectDirectory(arguments: [String: Any]) throws -> [String: Any] {
        let project = try requireProject(arguments)
        let path = try normalizedDirectory(requiredString(arguments, key: "workingDirectory"))
        guard let index = store.projects.firstIndex(where: { $0 === project }) else { throw MCPError("Project not found") }
        store.setWorkingDirectory(forProjectAt: index, to: URL(fileURLWithPath: path))
        return projectSnapshot(project)
    }

    private func selectProject(arguments: [String: Any]) throws -> [String: Any] {
        let project = try requireProject(arguments)
        guard let index = store.projects.firstIndex(where: { $0 === project }) else { throw MCPError("Project not found") }
        store.selectProject(at: index)
        return projectSnapshot(project)
    }

    private func deleteProject(arguments: [String: Any]) throws -> [String: Any] {
        guard arguments["confirm"] as? Bool == true else {
            throw MCPError("delete_project requires confirm=true")
        }
        let project = try requireProject(arguments)
        guard let index = store.projects.firstIndex(where: { $0 === project }) else { throw MCPError("Project not found") }
        let deletedID = project.id.uuidString
        store.deleteProject(at: index)
        return ["deletedProjectId": deletedID]
    }

    private func createTerminal(arguments: [String: Any]) throws -> [String: Any] {
        let targetProject: Project
        if let rawID = arguments["projectId"] as? String {
            guard let found = project(id: try uuid(rawID, label: "projectId")) else { throw MCPError("Project not found") }
            targetProject = found
        } else {
            guard let selected = store.selectedProject else { throw MCPError("No project is selected") }
            targetProject = selected
        }

        let directory: String?
        if let rawDirectory = arguments["workingDirectory"] as? String {
            directory = try normalizedDirectory(rawDirectory)
        } else {
            directory = nil
        }
        let shell = try normalizedShell(arguments["shell"] as? String)
        guard let session = store.addTerminal(to: targetProject, in: directory, shell: shell) else { throw MCPError("Could not create terminal") }
        return sessionSnapshot(session, project: targetProject)
    }

    private func closeTerminal(arguments: [String: Any]) throws -> [String: Any] {
        guard arguments["confirm"] as? Bool == true else {
            throw MCPError("close_terminal requires confirm=true")
        }
        let location = try requireSessionLocation(arguments)
        let closedID = location.session.id.uuidString
        store.removeTerminal(location.session)
        return ["closedSessionId": closedID]
    }

    private func moveTerminal(arguments: [String: Any]) throws -> [String: Any] {
        let location = try requireSessionLocation(arguments)
        let hasOffset = arguments["offset"] != nil
        let hasProject = arguments["projectId"] != nil
        guard hasOffset != hasProject else {
            throw MCPError("Provide exactly one of offset or projectId")
        }

        if let offset = integer(arguments["offset"]) {
            store.moveTerminal(location.session, by: offset)
        } else if let rawID = arguments["projectId"] as? String,
                  let target = project(id: try uuid(rawID, label: "projectId")) {
            store.moveTerminal(location.session, to: target)
        } else {
            throw MCPError("Destination project not found")
        }
        guard let updated = session(id: location.session.id) else { throw MCPError("Session not found") }
        return sessionSnapshot(updated.session, project: updated.project)
    }

    private func focus(arguments: [String: Any]) throws -> [String: Any] {
        let location = try requireSessionLocation(arguments)
        guard let index = store.projects.firstIndex(where: { $0 === location.project }) else { throw MCPError("Project not found") }
        store.selectProject(at: index)
        focusSession(location.session)
        return ["focusedSessionId": location.session.id.uuidString, "projectId": location.project.id.uuidString]
    }

    private func sendInput(arguments: [String: Any]) throws -> [String: Any] {
        let session = try requireSession(arguments)
        let text = try requiredString(arguments, key: "text")
        let enter = arguments["enter"] as? Bool ?? false
        let input = text + (enter ? "\r" : "")
        guard input.utf8.count <= Self.maxInputBytes else {
            throw MCPError("text is limited to 16 KiB per call")
        }
        guard session.isAlive else { throw MCPError("Session has exited") }
        session.writeInput(input)
        return ["sessionId": session.id.uuidString, "bytesSent": input.utf8.count, "enter": enter]
    }

    // MARK: Lookup / validation

    private func project(id: UUID) -> Project? {
        store.projects.first { $0.id == id }
    }

    private func session(id: UUID) -> SessionLocation? {
        for project in store.projects {
            if let session = project.sessions.first(where: { $0.id == id }) {
                return SessionLocation(project: project, session: session)
            }
        }
        return nil
    }

    private func requireProject(_ arguments: [String: Any]) throws -> Project {
        let id = try uuid(requiredString(arguments, key: "projectId"), label: "projectId")
        guard let project = project(id: id) else { throw MCPError("Project not found") }
        return project
    }

    private func requireSession(_ arguments: [String: Any]) throws -> TerminalSession {
        try requireSessionLocation(arguments).session
    }

    private func requireSessionLocation(_ arguments: [String: Any]) throws -> SessionLocation {
        let id = try uuid(requiredString(arguments, key: "sessionId"), label: "sessionId")
        guard let location = session(id: id) else { throw MCPError("Session not found") }
        return location
    }

    private func requiredString(_ arguments: [String: Any], key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw MCPError("\(key) is required")
        }
        return value
    }

    private func uuid(_ value: String, label: String) throws -> UUID {
        guard let value = UUID(uuidString: value) else { throw MCPError("\(label) must be a UUID") }
        return value
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func normalizedDirectory(_ rawPath: String) throws -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MCPError("Directory does not exist: \(url.path)")
        }
        return url.path
    }

    private func normalizedShell(_ rawPath: String?) throws -> String? {
        guard let rawPath else { return nil }
        let expanded = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw MCPError("Shell is not executable: \(url.path)")
        }
        let allowedNames = Set(["bash", "fish", "ksh", "sh", "zsh"])
        guard allowedNames.contains(url.lastPathComponent) else {
            throw MCPError("shell must be bash, fish, ksh, sh, or zsh")
        }
        return url.path
    }

    private func toolResult(_ value: Any, isError: Bool = false) -> [String: Any] {
        [
            "content": [["type": "text", "text": jsonString(value)]],
            "isError": isError
        ]
    }

    private func jsonString(_ value: Any) -> String {
        guard let data = jsonData(value), let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    private func jsonData(_ value: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    private func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
}
