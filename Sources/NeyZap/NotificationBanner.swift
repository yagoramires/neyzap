import AppKit

/// Notificação desenhada pelo próprio app: o macOS só troca o ícone do app pela foto
/// do remetente em apps com conta de desenvolvedor paga, então o NeyZap mostra um
/// balão no estilo do sistema com a foto do contato em destaque.
struct BannerContent {
    let accountID: UUID
    let jsID: String
    /// Mesma chave = mesma conversa: a notificação nova substitui a anterior.
    let key: String
    let account: String?
    let title: String
    let body: String
}

final class BannerCenter {
    static let shared = BannerCenter()

    /// (id da conta, id da notificação no JS)
    var onClick: ((UUID, String) -> Void)?

    static let size = NSSize(width: 380, height: 86)
    private let gap: CGFloat = 10
    private let margin: CGFloat = 12
    private let maxVisible = 4
    private var banners: [BannerPanel] = [] // o mais novo primeiro

    func show(_ content: BannerContent, icon: String) {
        Self.loadAvatar(icon) { [weak self] avatar in
            self?.present(content, avatar: avatar)
        }
    }

    /// Some com todos os balões de uma guia (guia fechada ou página recarregada).
    func dismissAll(accountID: UUID) {
        banners.filter { $0.content.accountID == accountID }.forEach { dismiss($0) }
    }

    func dismiss(accountID: UUID, jsID: String) {
        banners.filter { $0.content.accountID == accountID && $0.content.jsID == jsID }.forEach { dismiss($0) }
    }

    // MARK: - Internos

    private func present(_ content: BannerContent, avatar: NSImage?) {
        if let existing = banners.first(where: { $0.content.key == content.key }) {
            existing.update(content, avatar: avatar)
            banners.removeAll { $0 === existing }
            banners.insert(existing, at: 0)
            layout(animated: true)
            return
        }

        let banner = BannerPanel(content: content, avatar: avatar)
        banner.onClick = { [weak self, weak banner] in
            guard let self, let banner else { return }
            self.onClick?(banner.content.accountID, banner.content.jsID)
            self.dismiss(banner)
        }
        banner.onClose = { [weak self, weak banner] in
            if let banner { self?.dismiss(banner) }
        }
        banner.onExpire = banner.onClose

        banners.insert(banner, at: 0)
        while banners.count > maxVisible, let oldest = banners.last { dismiss(oldest) }

        let target = frame(at: 0)
        banner.setFrame(target.offsetBy(dx: 40, dy: 0), display: false)
        banner.alphaValue = 0
        banner.orderFrontRegardless()
        layout(animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            banner.animator().setFrame(target, display: true)
            banner.animator().alphaValue = 1
        }
        banner.startTimer()
    }

    private func dismiss(_ banner: BannerPanel) {
        guard let index = banners.firstIndex(where: { $0 === banner }) else { return }
        banners.remove(at: index)
        banner.stopTimer()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            banner.animator().alphaValue = 0
            banner.animator().setFrame(banner.frame.offsetBy(dx: 40, dy: 0), display: true)
        }, completionHandler: {
            banner.orderOut(nil)
        })
        layout(animated: true)
    }

    private func layout(animated: Bool) {
        for (i, banner) in banners.enumerated() {
            let target = frame(at: i)
            if banner.frame.origin.y == target.origin.y { continue }
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    banner.animator().setFrame(target, display: true)
                }, completionHandler: { banner.refreshHoverFromMouse() })
            } else {
                banner.setFrame(target, display: true)
            }
        }
    }

    /// Canto superior direito da tela da barra de menus, empilhando para baixo.
    private func frame(at index: Int) -> NSRect {
        let screen = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = Self.size
        let y = screen.maxY - margin - size.height - CGFloat(index) * (size.height + gap)
        let m = BannerPanel.margin
        return NSRect(x: screen.maxX - margin - size.width - m, y: y - m, width: size.width + m * 2, height: size.height + m * 2)
    }

    private static func loadAvatar(_ source: String, completion: @escaping (NSImage?) -> Void) {
        if source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") {
            let data = Data(base64Encoded: String(source[source.index(after: comma)...]))
            completion(data.flatMap(NSImage.init(data:)))
            return
        }
        guard let url = URL(string: source), url.scheme == "https",
              let host = url.host?.lowercased(), ["whatsapp.net", "whatsapp.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            completion(nil)
            return
        }
        var finished = false
        let finish: (NSImage?) -> Void = { image in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(image)
            }
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in finish(data.flatMap(NSImage.init(data:))) }.resume()
        // Sem esperar muito pela foto: a notificação sai mesmo sem ela.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { finish(nil) }
    }
}

// MARK: - Painel

final class BannerPanel: NSPanel {
    private(set) var content: BannerContent
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    var onExpire: (() -> Void)?

    /// Margem transparente em volta do balão, para o X poder ficar sobre a borda.
    static let margin: CGFloat = 8

    private let avatarView = AvatarFillView()
    private let accountLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "agora")
    private let closeButton = CloseCircleView()
    private var timer: Timer?
    private static let lifetime: TimeInterval = 6

    init(content: BannerContent, avatar: NSImage?) {
        self.content = content
        let m = Self.margin
        let size = NSSize(width: BannerCenter.size.width + m * 2, height: BannerCenter.size.height + m * 2)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        buildViews()
        update(content, avatar: avatar)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(_ content: BannerContent, avatar: NSImage?) {
        self.content = content
        if let avatar { avatarView.image = avatar } // sem foto nova, mantém a que já estava
        avatarView.fallbackText = content.title
        accountLabel.stringValue = content.account ?? ""
        accountLabel.isHidden = content.account == nil
        titleLabel.stringValue = content.title
        bodyLabel.stringValue = content.body
        startTimer()
    }

    /// Com o mouse em cima o balão não some (o tempo volta a correr quando o mouse sai).
    private(set) var hovering = false

    func startTimer() {
        timer?.invalidate()
        guard !hovering else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.lifetime, repeats: false) { [weak self] _ in self?.onExpire?() }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func setHovering(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        closeButton.isHidden = !inside
        if inside { stopTimer() } else { startTimer() }
    }

    /// Depois de mudar de posição (outro balão saiu da pilha), confere se ficou
    /// embaixo do cursor — nesse caso o sistema não avisa a entrada do mouse.
    func refreshHoverFromMouse() {
        setHovering(frame.contains(NSEvent.mouseLocation))
    }

    private func buildViews() {
        let size = BannerCenter.size
        let m = Self.margin
        let container = BannerContainerView(frame: NSRect(x: 0, y: 0, width: size.width + m * 2, height: size.height + m * 2))
        container.onHover = { [weak self] inside in self?.setHovering(inside) }
        contentView = container

        let root = BannerRootView(frame: NSRect(x: m, y: m, width: size.width, height: size.height))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.maskImage = Self.roundedMask(radius: 18)
        root.onClick = { [weak self] in self?.onClick?() }
        container.addSubview(root)

        // Foto grande, com margem e cantos arredondados como os ícones do macOS.
        let inset: CGFloat = 11
        let photo = size.height - inset * 2
        avatarView.frame = NSRect(x: inset, y: inset, width: photo, height: photo)
        avatarView.wantsLayer = true
        avatarView.layer?.cornerRadius = 14
        avatarView.layer?.cornerCurve = .continuous
        avatarView.layer?.masksToBounds = true
        root.addSubview(avatarView)

        accountLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        accountLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .labelColor
        bodyLabel.maximumNumberOfLines = 2
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.cell?.truncatesLastVisibleLine = true
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [accountLabel, titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.setCustomSpacing(2, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        root.addSubview(timeLabel)

        let textLeft: CGFloat = inset + photo + 12
        bodyLabel.preferredMaxLayoutWidth = size.width - textLeft - 14
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: textLeft),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: size.width - textLeft - 14),
            timeLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            timeLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
        ])

        // X como o do sistema: círculo sobre o canto superior esquerdo, só com o mouse em cima.
        let d = CloseCircleView.diameter
        closeButton.frame = NSRect(x: m + 2 - d / 2, y: m + size.height - 2 - d / 2, width: d, height: d)
        closeButton.onClick = { [weak self] in self?.onClose?() }
        closeButton.isHidden = true
        container.addSubview(closeButton)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Área transparente em volta do balão; acompanha o mouse para mostrar o X.
private final class BannerContainerView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Botão redondo de fechar, no estilo das notificações do macOS.
private final class CloseCircleView: NSView {
    static let diameter: CGFloat = 20
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base: CGFloat = dark ? (hovering ? 0.32 : 0.24) : (hovering ? 0.84 : 0.92)
        NSColor(white: base, alpha: 1).setFill()
        circle.fill()
        NSColor.separatorColor.setStroke()
        circle.lineWidth = 1
        circle.stroke()
        guard let glyph = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar")?
            .withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold)) else { return }
        let tinted = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            (self.hovering ? NSColor.labelColor : NSColor.secondaryLabelColor).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: bounds.midX - glyph.size.width / 2, y: bounds.midY - glyph.size.height / 2,
                               width: glyph.size.width, height: glyph.size.height))
    }
}

/// Fundo translúcido que trata clique e hover do balão inteiro.
private final class BannerRootView: NSVisualEffectView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Foto preenchendo a área (recorte central, sem distorcer). Sem foto, mostra as
/// iniciais sobre um degradê.
final class AvatarFillView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var fallbackText = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        if let image, image.size.width > 0, image.size.height > 0 {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }
        NSGradient(starting: NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.42, alpha: 1),
                   ending: NSColor(calibratedRed: 0.05, green: 0.45, blue: 0.35, alpha: 1))?.draw(in: bounds, angle: -60)
        let initials = fallbackText.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        let text = initials.isEmpty ? "?" : initials
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: bounds.height * 0.34, weight: .semibold), .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2), withAttributes: attrs)
    }
}
