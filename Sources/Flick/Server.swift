import Foundation
import Network

/// Servidor HTTP mínimo na rede local.
/// GET /          -> página que o iPhone abre no Safari
/// POST /upload   -> corpo cru do arquivo (?name=arquivo.ext)
/// POST /text     -> texto que vai para a área de transferência do Mac
final class FlickServer {
    let port: UInt16
    let saveDirectory: URL
    var onFile: (@Sendable (URL) -> Void)?
    var onText: (@Sendable (String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "flick.server")
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    init(port: UInt16, saveDirectory: URL) {
        self.port = port
        self.saveDirectory = saveDirectory
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "Flick", code: 1, userInfo: [NSLocalizedDescriptionKey: "Porta inválida"])
        }
        let l = try NWListener(using: params, on: nwPort)
        l.service = NWListener.Service(name: "Flick", type: "_http._tcp")
        l.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            let h = HTTPConnection(connection: c, server: self)
            self.connections[ObjectIdentifier(h)] = h
            h.start(on: self.queue)
        }
        l.start(queue: queue)
        listener = l
    }

    fileprivate func remove(_ c: HTTPConnection) {
        connections[ObjectIdentifier(c)] = nil
    }

    fileprivate func uniqueDestination(for rawName: String) -> URL {
        var name = (rawName as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "arquivo" + name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = saveDirectory.appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = saveDirectory.appendingPathComponent(next)
            i += 1
        }
        return candidate
    }
}

/// Log em stderr (sem buffer) para diagnosticar envios do iPhone.
func flickLog(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

final class HTTPConnection {
    private let conn: NWConnection
    private unowned let server: FlickServer

    private var head = Data()
    private var headerDone = false
    private var method = ""
    private var path = ""
    private var query: [String: String] = [:]
    private var expected = 0
    private var received = 0
    private var handle: FileHandle?
    private var fileURL: URL?
    private var body = Data()
    private var finished = false

    init(connection: NWConnection, server: FlickServer) {
        self.conn = connection
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                flickLog("conexao falhou \(self.method) \(self.path) recebido=\(self.received)/\(self.expected): \(error)")
                self.discardPartial()
                self.server.remove(self)
            case .cancelled:
                if self.fileURL != nil {
                    flickLog("envio interrompido \(self.path) recebido=\(self.received)/\(self.expected)")
                }
                self.discardPartial()
                self.server.remove(self)
            default:
                break
            }
        }
        conn.start(queue: queue)
        read()
    }

    private func read() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty { self.consume(data) }
            if self.finished { return }
            if error != nil || isComplete {
                self.finished = true
                self.conn.cancel()
                return
            }
            self.read()
        }
    }

    private func consume(_ data: Data) {
        if headerDone {
            consumeBody(data)
            return
        }
        head.append(data)
        guard let range = head.range(of: Data("\r\n\r\n".utf8)) else {
            if head.count > 65_536 { respond(status: "431 Request Header Fields Too Large", text: "cabecalho grande demais") }
            return
        }
        let headerData = head.subdata(in: head.startIndex..<range.lowerBound)
        let rest = head.subdata(in: range.upperBound..<head.endIndex)
        head = Data()
        headerDone = true
        guard parseHeader(headerData) else {
            respond(status: "400 Bad Request", text: "requisicao invalida")
            return
        }
        route()
        if finished { return }
        if !rest.isEmpty { consumeBody(rest) }
    }

    private func parseHeader(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return false }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return false }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return false }
        method = String(parts[0]).uppercased()
        let target = String(parts[1])
        if let comps = URLComponents(string: "http://localhost" + target) {
            path = comps.path
            for item in comps.queryItems ?? [] { query[item.name] = item.value ?? "" }
        } else {
            path = target
        }
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            if key == "content-length" { expected = Int(value) ?? 0 }
        }
        return true
    }

    private func route() {
        if path != "/ping" {
            flickLog("\(method) \(path) name=\(query["name"] ?? "-") content-length=\(expected) de \(conn.endpoint)")
        }
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            respond(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(webPageHTML.utf8))
        case ("GET", "/ping"):
            respond(status: "200 OK", text: "ok")
        case ("POST", "/upload"):
            guard expected > 0 else {
                respond(status: "400 Bad Request", text: "arquivo vazio")
                return
            }
            let dest = server.uniqueDestination(for: query["name"] ?? "arquivo")
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            guard let h = try? FileHandle(forWritingTo: dest) else {
                respond(status: "500 Internal Server Error", text: "nao consegui gravar")
                return
            }
            handle = h
            fileURL = dest
        case ("POST", "/text"):
            guard expected > 0, expected <= 1_000_000 else {
                respond(status: "400 Bad Request", text: "texto invalido")
                return
            }
        default:
            respond(status: "404 Not Found", text: "nao encontrado")
        }
    }

    private func consumeBody(_ data: Data) {
        if let handle {
            do {
                try handle.write(contentsOf: data)
            } catch {
                discardPartial()
                respond(status: "500 Internal Server Error", text: "erro ao gravar")
                return
            }
        } else {
            body.append(data)
        }
        received += data.count
        if received >= expected { complete() }
    }

    private func complete() {
        if let handle, let url = fileURL {
            try? handle.close()
            self.handle = nil
            self.fileURL = nil
            flickLog("arquivo salvo: \(url.lastPathComponent) (\(received) bytes)")
            server.onFile?(url)
            respond(status: "200 OK", text: "ok")
        } else {
            let text = String(data: body, encoding: .utf8) ?? ""
            if !text.isEmpty { server.onText?(text) }
            respond(status: "200 OK", text: "ok")
        }
    }

    private func discardPartial() {
        if let handle { try? handle.close() }
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        handle = nil
        fileURL = nil
    }

    private func respond(status: String, text: String) {
        respond(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    private func respond(status: String, contentType: String, body: Data) {
        guard !finished else { return }
        finished = true
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        let c = conn
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}

/// Endereços IPv4 do Mac na rede local (Wi-Fi/Ethernet).
func localIPv4Addresses() -> [String] {
    var result: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let ifa = p.pointee
        ptr = ifa.ifa_next
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
        let flags = Int32(ifa.ifa_flags)
        guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
        let name = String(cString: ifa.ifa_name)
        guard name.hasPrefix("en") else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            result.append(String(cString: host))
        }
    }
    return result
}
