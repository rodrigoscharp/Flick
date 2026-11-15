import AppKit
import SwiftUI
import QuickLookThumbnailing

// Chegada de um item: uma aura colorida acende colada na borda direita da tela, a foto sai
// de dentro dela, faz uma curva até o notch e vira uma ilha preta que sai do próprio notch.
// Clicar na ilha mostra o arquivo no Finder.

struct ArrivalItem {
    let image: NSImage?
    let symbol: String
    let title: String
    let subtitle: String
    let onClick: () -> Void
}

/// Geometria da tela de destino, em coordenadas SwiftUI (origem no canto superior esquerdo).
struct NotchGeometry {
    let screen: CGRect
    let notch: CGRect
    let islandSize: CGSize

    static let contentHeight: CGFloat = 84

    init(screen nsScreen: NSScreen) {
        let f = nsScreen.frame
        screen = f
        let top = nsScreen.safeAreaInsets.top
        var notchWidth: CGFloat = 0
        if top > 0, let left = nsScreen.auxiliaryTopLeftArea, let right = nsScreen.auxiliaryTopRightArea {
            notchWidth = f.width - left.width - right.width
        }
        if notchWidth <= 0 { notchWidth = 180 }
        notch = CGRect(x: (f.width - notchWidth) / 2, y: 0, width: notchWidth, height: max(top, 0))
        islandSize = CGSize(width: max(notchWidth + 120, 340), height: notch.height + NotchGeometry.contentHeight)
    }

    /// Centro da miniatura dentro da ilha aberta.
    var thumbCenter: CGPoint {
        CGPoint(x: notch.midX - islandSize.width / 2 + 16 + 26, y: notch.height + NotchGeometry.contentHeight / 2)
    }

    /// Retângulo da ilha aberta em coordenadas AppKit (origem embaixo), para a janela clicável.
    var islandFrame: NSRect {
        NSRect(
            x: screen.minX + notch.midX - islandSize.width / 2,
            y: screen.maxY - islandSize.height,
            width: islandSize.width,
            height: islandSize.height
        )
    }
}

/// Painel sem borda acima da barra de menus, para poder encostar no notch.
final class TopPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

// MARK: - Peças visuais

/// Ilha com cantos de cima retos (somem no notch) e cantos de baixo arredondados.
struct IslandShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Miniatura + nome + tamanho, usado dentro da ilha.
struct ArrivalContent: View {
    let item: ArrivalItem

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.12))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

/// A foto no formato real dela; sem foto, um cartão escuro com o nome do arquivo.
struct ArrivalCardView: View {
    let item: ArrivalItem

    var body: some View {
        Group {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 34, weight: .medium))
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 8)
    }
}

/// Aura colorida colada na borda direita: nasce de fora da tela e brilha forte na borda.
struct EdgeAura: View {
    let height: CGFloat
    let grow: Double

    private let colors: [Color] = [
        Color(red: 0.25, green: 0.45, blue: 1.00),
        Color(red: 0.60, green: 0.35, blue: 1.00),
        Color(red: 1.00, green: 0.35, blue: 0.65),
        Color(red: 1.00, green: 0.60, blue: 0.25),
        Color(red: 0.20, green: 0.85, blue: 1.00),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.92 + 0.08 * sin(t * 3)
            ZStack(alignment: .trailing) {
                // Halo largo girando, metade fora da tela.
                Ellipse()
                    .fill(AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(t * 60)))
                    .frame(width: 320, height: height)
                    .offset(x: 160)
                    .blur(radius: 50)
                // Núcleo saturado.
                Ellipse()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 150, height: height * 0.8)
                    .offset(x: 75)
                    .blur(radius: 24)
                // Linha de luz na borda, como uma fenda se abrindo.
                Capsule()
                    .fill(LinearGradient(colors: [colors[4], .white, colors[2]], startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: height * 0.7)
                    .blur(radius: 3)
            }
            .frame(width: 420, height: height * 1.2, alignment: .trailing)
            .scaleEffect(x: CGFloat(grow), y: CGFloat(0.5 + 0.5 * grow), anchor: .trailing)
            .opacity(grow * pulse)
        }
    }
}

// MARK: - Voo

@MainActor
final class FlightModel: ObservableObject {
    @Published var aura: Double = 0
    @Published var cardX: CGFloat = 0
    @Published var cardY: CGFloat = 0
    @Published var cardScale: CGFloat = 1
    @Published var cardOpacity: Double = 1
    @Published var island: CGSize = .zero
    @Published var islandContent: Double = 0
}

struct FlightView: View {
    @ObservedObject var model: FlightModel
    let geo: NotchGeometry
    let item: ArrivalItem
    let cardSize: CGSize
    let entryY: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            EdgeAura(height: geo.screen.height * 0.6, grow: model.aura)
                .position(x: geo.screen.width - 210, y: entryY)

            IslandShape(radius: 24)
                .fill(Color.black)
                .frame(width: model.island.width, height: model.island.height)
                .overlay(
                    ArrivalContent(item: item)
                        .frame(height: NotchGeometry.contentHeight)
                        .opacity(model.islandContent),
                    alignment: .bottom
                )
                .position(x: geo.notch.midX, y: model.island.height / 2)

            ArrivalCardView(item: item)
                .frame(width: cardSize.width, height: cardSize.height)
                .scaleEffect(model.cardScale)
                .opacity(model.cardOpacity)
                .position(x: model.cardX, y: model.cardY)
        }
        .frame(width: geo.screen.width, height: geo.screen.height, alignment: .topLeading)
    }
}

// MARK: - Ilha parada (clicável)

@MainActor
final class IslandModel: ObservableObject {
    @Published var size: CGSize
    @Published var content: Double = 1
    init(size: CGSize) { self.size = size }
}

struct DockedIsland: View {
    @ObservedObject var model: IslandModel
    let geo: NotchGeometry
    let item: ArrivalItem

    var body: some View {
        IslandShape(radius: 24)
            .fill(Color.black)
            .frame(width: model.size.width, height: model.size.height)
            .overlay(
                ArrivalContent(item: item)
                    .frame(height: NotchGeometry.contentHeight)
                    .opacity(model.content),
                alignment: .bottom
            )
            .frame(width: geo.islandSize.width, height: geo.islandSize.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { item.onClick() }
    }
}

// MARK: - Orquestração

@MainActor
final class ArrivalOverlay {
    private var queue: [ArrivalItem] = []
    private var playing = false

    func showFile(_ url: URL, from origin: String = "Recebido do iPhone") {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let subtitle = origin + " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let title = url.lastPathComponent
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 500, height: 500),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            let image = rep?.nsImage
            Task { @MainActor in
                self.present(image: image, symbol: "doc.fill", title: title, subtitle: subtitle) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    func present(image: NSImage?, symbol: String, title: String, subtitle: String, onClick: @escaping () -> Void) {
        queue.append(ArrivalItem(image: image, symbol: symbol, title: title, subtitle: subtitle, onClick: onClick))
        if !playing { playNext() }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            playing = false
            return
        }
        playing = true
        let item = queue.removeFirst()
        Task { @MainActor in
            await self.play(item)
            self.playNext()
        }
    }

    /// Prefere a tela com notch; sem notch, usa a principal.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func play(_ item: ArrivalItem) async {
        guard let screen = targetScreen() else { return }
        let geo = NotchGeometry(screen: screen)
        let w = geo.screen.width
        let entryY = geo.screen.height * 0.45

        // Foto no formato real, com altura de ~26% da tela.
        let cardH = (geo.screen.height * 0.26).rounded()
        var aspect: CGFloat = 0.75
        if let img = item.image, img.size.height > 0 { aspect = min(max(img.size.width / img.size.height, 0.5), 1.6) }
        let cardSize = CGSize(width: (cardH * aspect).rounded(), height: cardH)

        let model = FlightModel()
        model.cardX = w + cardSize.width / 2 + 10
        model.cardY = entryY
        model.island = geo.notch.size

        let fx = TopPanel(frame: geo.screen)
        fx.ignoresMouseEvents = true
        fx.contentView = NSHostingView(rootView: FlightView(model: model, geo: geo, item: item, cardSize: cardSize, entryY: entryY))
        fx.orderFrontRegardless()

        // 1. A aura acende colada na borda direita.
        withAnimation(.easeOut(duration: 0.35)) { model.aura = 1 }
        await wait(0.18)

        // 2. A foto sai de dentro da aura, devagar.
        withAnimation(.timingCurve(0.2, 0.7, 0.3, 1.0, duration: 0.5)) {
            model.cardX = w - cardSize.width / 2 - 70
        }
        // Pausa curta, só para ver o que chegou.
        await wait(0.45)

        // 3. A aura se apaga e a foto faz a curva até o notch, encolhendo até virar a miniatura da ilha.
        withAnimation(.easeIn(duration: 0.4)) { model.aura = 0 }
        withAnimation(.timingCurve(0.3, 0.0, 0.2, 1.0, duration: 0.55)) { model.cardX = geo.thumbCenter.x }
        withAnimation(.timingCurve(0.7, 0.0, 0.5, 1.0, duration: 0.55)) {
            model.cardY = geo.thumbCenter.y
            model.cardScale = 52 / cardH
        }
        await wait(0.28)

        // 4. A ilha sai do notch para receber a foto.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { model.island = geo.islandSize }
        await wait(0.24)
        withAnimation(.easeOut(duration: 0.12)) {
            model.cardOpacity = 0
            model.islandContent = 1
        }
        await wait(0.14)

        // 5. Troca para a ilha parada, que aceita clique.
        let islandModel = IslandModel(size: geo.islandSize)
        let dock = TopPanel(frame: geo.islandFrame)
        dock.contentView = NSHostingView(rootView: DockedIsland(model: islandModel, geo: geo, item: item))
        dock.orderFrontRegardless()
        fx.orderOut(nil)

        await wait(3.5)

        // 6. A ilha volta para dentro do notch.
        withAnimation(.easeOut(duration: 0.15)) { islandModel.content = 0 }
        await wait(0.1)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { islandModel.size = geo.notch.size }
        await wait(0.45)
        dock.orderOut(nil)
    }
}
