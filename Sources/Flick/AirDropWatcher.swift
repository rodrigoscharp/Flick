import Foundation

/// Observa a pasta Downloads e avisa quando chega um arquivo por AirDrop.
/// AirDrop é conexão direta iPhone -> Mac (Bluetooth + Wi-Fi ponto a ponto),
/// então funciona sem roteador e já vem pareado pelo Apple ID.
final class AirDropWatcher {
    let directory: URL
    var onFile: (@Sendable (URL) -> Void)?

    private let queue = DispatchQueue(label: "flick.airdrop")
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pending: Set<String> = []

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) {
        self.directory = directory
    }

    func start() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            flickLog("AirDrop: sem acesso a \(directory.path)")
            return
        }
        known = Set(listing())
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        s.setEventHandler { [weak self] in self?.scan() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
        flickLog("AirDrop: observando \(directory.path)")
    }

    private func listing() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func scan() {
        let current = Set(listing())
        let added = current.subtracting(known).subtracting(pending)
        known = current
        for name in added where !name.hasPrefix(".") && !isPartial(name) {
            pending.insert(name)
            waitUntilStable(name, lastSize: -1, tries: 0)
        }
    }

    private func isPartial(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["download", "crdownload", "part", "partial", "tmp"].contains(ext)
    }

    /// Espera o tamanho parar de mudar antes de mostrar a animação.
    private func waitUntilStable(_ name: String, lastSize: Int, tries: Int) {
        queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let url = self.directory.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]).fileSize ?? 0 else {
                self.pending.remove(name)
                return
            }
            if size != lastSize, tries < 200 {
                self.waitUntilStable(name, lastSize: size, tries: tries + 1)
                return
            }
            self.pending.remove(name)
            let agent = self.quarantineAgent(url)
            flickLog("AirDrop: novo arquivo \(name) agente=\(agent ?? "-")")
            if self.cameFromAirDrop(agent: agent) { self.onFile?(url) }
        }
    }

    /// Download de navegador traz o nome do navegador na quarentena; AirDrop traz o sharingd.
    private func cameFromAirDrop(agent: String?) -> Bool {
        guard let agent else { return true }
        let a = agent.lowercased()
        return a.contains("sharingd") || a.contains("airdrop")
    }

    private func quarantineAgent(_ url: URL) -> String? {
        let name = "com.apple.quarantine"
        let len = getxattr(url.path, name, nil, 0, 0, 0)
        guard len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard getxattr(url.path, name, &buf, len, 0, 0) == len else { return nil }
        let parts = String(decoding: buf, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        return parts.count > 2 ? String(parts[2]) : nil
    }
}
