import AppKit
import SwiftUI
import CoreImage
import SystemConfiguration

@main
struct FlickMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16 = 8787
    private let saveDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Flick")
    private let overlay = ArrivalOverlay()
    private var statusItem: NSStatusItem?
    private var server: FlickServer?
    private var pairWindow: NSWindow?
    private let airDrop = AirDropWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)

        let server = FlickServer(port: port, saveDirectory: saveDirectory)
        server.onFile = { [weak self] url in
            Task { @MainActor in self?.overlay.showFile(url) }
        }
        server.onText = { [weak self] text in
            Task { @MainActor in self?.textArrived(text) }
        }
        do {
            try server.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não consegui iniciar o Flick"
            alert.informativeText = "A porta \(port) pode estar em uso. \(error.localizedDescription)"
            alert.runModal()
        }
        self.server = server

        airDrop.onFile = { [weak self] url in
            Task { @MainActor in self?.overlay.showFile(url, from: "Recebido por AirDrop") }
        }
        airDrop.start()

        setupMenu()
        showPairWindow()
    }

    /// Endereço fixo via Bonjour (nome.local): continua valendo quando o IP do Mac muda,
    /// então o atalho na Tela de Início do iPhone só precisa ser criado uma vez.
    private var pairURL: String {
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String? {
            return "http://\(name).local:\(port)"
        }
        return ipURL
    }

    private var ipURL: String {
        let ip = localIPv4Addresses().first ?? "IP-DO-MAC"
        return "http://\(ip):\(port)"
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Flick") {
            item.button?.image = image
        } else {
            item.button?.title = "Flick"
        }
        let menu = NSMenu()
        menu.addItem(makeItem("Conectar iPhone…", #selector(showPairWindow)))
        menu.addItem(makeItem("Abrir pasta de recebidos", #selector(openFolder)))
        menu.addItem(makeItem("Testar animação", #selector(testAnimation)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Sair", #selector(quit)))
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func textArrived(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let preview = text.replacingOccurrences(of: "\n", with: " ")
        overlay.present(image: nil, symbol: "doc.on.clipboard.fill", title: "Texto copiado", subtitle: String(preview.prefix(60))) {}
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(saveDirectory)
    }

    @objc private func testAnimation() {
        let sample = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic")
        if FileManager.default.fileExists(atPath: sample.path) {
            overlay.showFile(sample, from: "Teste")
        } else {
            overlay.present(image: nil, symbol: "photo.fill", title: "Teste.jpg", subtitle: "Recebido do iPhone · 2,4 MB") {}
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showPairWindow() {
        let url = pairURL
        let view = PairView(url: url, fallbackURL: ipURL, qr: makeQRCode(url))
        if let window = pairWindow {
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 470),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Flick"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.makeKeyAndOrderFront(nil)
            pairWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeQRCode(_ string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct PairView: View {
    let url: String
    let fallbackURL: String
    let qr: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            Text("Conectar o iPhone")
                .font(.system(size: 17, weight: .semibold))
            if let qr {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(url)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
            Text("Se não abrir: \(fallbackURL)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Text("Com o iPhone no mesmo Wi-Fi, aponte a câmera para o código. No Safari, toque em Compartilhar e em “Adicionar à Tela de Início”. Só precisa fazer isso uma vez.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 340, height: 470)
    }
}
