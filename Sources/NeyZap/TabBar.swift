import AppKit

/// Guias no estilo navegador: uma por número, com inicial colorida, nome, selos de
/// não lidas/arquivadas, × no hover e + para abrir outra. Duplo clique renomeia.
final class TabBarView: NSView {
    struct Tab: Equatable {
        let id: UUID
        var name: String
        var unread: Int
        var archived: Int
    }

    var onSelect: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onResetSession: ((UUID) -> Void)?
    /// Terminou de renomear (para devolver o foco ao WhatsApp).
    var onEditingEnded: (() -> Void)?
    /// Largura máxima (a janela informa ao mudar de tamanho): acima disso os nomes encolhem.
    var maxWidth: CGFloat = .greatestFiniteMagnitude { didSet { invalidateIntrinsicContentSize() } }

    private let stack = NSStackView()
    private let addButton = NSButton()
    private var items: [TabItemView] = []
    private(set) var tabs: [Tab] = []
    private var selectedID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Nova guia")
        addButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.toolTip = "Nova guia (⌘T)"
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        addButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [Tab], selected: UUID?) {
        let structureChanged = tabs.map(\.id) != self.tabs.map(\.id)
        self.tabs = tabs
        selectedID = selected
        if structureChanged {
            items.forEach { $0.removeFromSuperview() }
            addButton.removeFromSuperview()
            items = tabs.map { tab in
                let item = TabItemView(tab: tab)
                item.onSelect = { [weak self] in self?.onSelect?(tab.id) }
                item.onClose = { [weak self] in self?.onClose?(tab.id) }
                item.onRename = { [weak self] name in self?.onRename?(tab.id, name) }
                item.onResetSession = { [weak self] in self?.onResetSession?(tab.id) }
                item.onEditingEnded = { [weak self] in self?.onEditingEnded?() }
                stack.addArrangedSubview(item)
                return item
            }
            stack.addArrangedSubview(addButton)
        }
        for (item, tab) in zip(items, tabs) {
            item.tab = tab
            item.isSelected = tab.id == selected
            item.canClose = tabs.count > 1
        }
        invalidateIntrinsicContentSize()
        // Guias novas ou que mudaram de lugar só têm tamanho depois do layout.
        DispatchQueue.main.async { [weak self] in
            self?.layoutSubtreeIfNeeded()
            self?.items.forEach { $0.refreshHoverFromMouse() }
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: min(stack.fittingSize.width, maxWidth), height: 28)
    }

    @objc private func addTapped() { onAdd?() }
}

// MARK: - Guia

private final class TabItemView: NSView, NSTextFieldDelegate {
    var tab: TabBarView.Tab { didSet { refresh() } }
    var isSelected = false { didSet { needsDisplay = true } }
    var canClose = true { didSet { refreshClose() } }
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onResetSession: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    private let avatar = InitialBadgeView()
    private let label = NSTextField(labelWithString: "")
    private let unreadBadge = CountBadgeView(color: .systemRed)
    private let archivedBadge = CountBadgeView(color: .systemGray, symbol: "archivebox.fill")
    private let closeButton = NSButton()
    private var hovering = false { didSet { needsDisplay = true; refreshClose() } }
    private var editingOriginal: String?

    init(tab: TabBarView.Tab) {
        self.tab = tab
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.delegate = self
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar guia")
        closeButton.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Fechar guia"
        closeButton.target = self
        closeButton.action = #selector(closeTapped)

        let row = NSStackView(views: [avatar, label, unreadBadge, archivedBadge, closeButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.setCustomSpacing(4, after: unreadBadge)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
            avatar.widthAnchor.constraint(equalToConstant: 18),
            avatar.heightAnchor.constraint(equalToConstant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        avatar.text = tab.name
        avatar.color = Self.color(for: tab.id)
        if editingOriginal == nil { label.stringValue = tab.name }
        unreadBadge.count = tab.unread
        archivedBadge.count = tab.archived
        var tip = tab.name
        if tab.unread > 0 { tip += " · \(tab.unread) não lida(s)" }
        if tab.archived > 0 { tip += " · \(tab.archived) arquivada(s)" }
        toolTip = tip + "\nDuplo clique para renomear"
    }

    private func refreshClose() {
        // Mantém o espaço reservado para a guia não pular de largura no hover.
        closeButton.alphaValue = canClose && (hovering || isSelected) ? 1 : 0
        closeButton.isEnabled = canClose
    }

    /// Cor estável por guia (não muda ao renomear).
    private static func color(for id: UUID) -> NSColor {
        let palette: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemIndigo, .systemRed]
        let sum = withUnsafeBytes(of: id.uuid) { $0.reduce(0) { $0 + Int($1) } }
        return palette[sum % palette.count]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || hovering else { return }
        NSColor.labelColor.withAlphaComponent(isSelected ? 0.11 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 0.5), xRadius: 7, yRadius: 7).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// Depois de um aviso modal (confirmar fechamento) ou de uma guia sumir, o sistema
    /// não avisa a saída do mouse: confere a posição real.
    func refreshHoverFromMouse() {
        guard let window else { hovering = false; return }
        hovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            beginEditing()
        } else if editingOriginal == nil {
            onSelect?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Não seleciona a guia: trazê-la para a tela marcaria as mensagens como lidas.
        let menu = NSMenu()
        menu.addItem(withTitle: "Renomear guia", action: #selector(renameFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Limpar sessão (novo QR code)…", action: #selector(resetFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let close = menu.addItem(withTitle: "Fechar guia…", action: canClose ? #selector(closeTapped) : nil, keyEquivalent: "")
        close.target = self
        menu.items.forEach { $0.target = self }
        return menu
    }

    // MARK: Renomear

    func beginEditing() {
        guard editingOriginal == nil else { return }
        editingOriginal = tab.name
        label.isEditable = true
        label.isSelectable = true
        label.drawsBackground = true
        label.backgroundColor = .textBackgroundColor
        label.isBezeled = false
        window?.makeFirstResponder(label)
        label.currentEditor()?.selectAll(nil)
    }

    /// `refocus`: Enter/Esc devolvem o foco ao WhatsApp; um clique em outro lugar
    /// deixa o foco onde o clique o pôs.
    private func endEditing(commit: Bool, refocus: Bool) {
        guard let original = editingOriginal else { return }
        editingOriginal = nil
        let name = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        if commit, !name.isEmpty, name != original {
            onRename?(name)
        } else {
            label.stringValue = original
        }
        if refocus { onEditingEnded?() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing(commit: false, refocus: true)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            endEditing(commit: true, refocus: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing(commit: true, refocus: false)
    }

    @objc private func renameFromMenu() { beginEditing() }
    @objc private func resetFromMenu() { onResetSession?() }
    @objc private func closeTapped() {
        onClose?()
        refreshHoverFromMouse()
    }
}

// MARK: - Peças

/// Quadradinho colorido com a inicial do nome da guia.
private final class InitialBadgeView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4.5, yRadius: 4.5).fill()
        let initial = text.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10.5, weight: .bold), .foregroundColor: NSColor.white]
        let size = initial.size(withAttributes: attrs)
        initial.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

/// Selo arredondado com contagem (some quando é zero).
private final class CountBadgeView: NSView {
    var count = 0 { didSet { isHidden = count == 0; invalidateIntrinsicContentSize(); needsDisplay = true } }
    private let color: NSColor
    private let icon: NSImage?
    private let font = NSFont.systemFont(ofSize: 10.5, weight: .bold)

    init(color: NSColor, symbol: String? = nil) {
        self.color = color
        icon = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold)) }
        super.init(frame: .zero)
        isHidden = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var text: String { count > 99 ? "99+" : "\(count)" }

    override var intrinsicContentSize: NSSize {
        let textWidth = text.size(withAttributes: [.font: font]).width
        let iconWidth = icon.map { $0.size.width + 3 } ?? 0
        return NSSize(width: max(16, ceil(textWidth + iconWidth + 9)), height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)
        var x = bounds.midX - (textSize.width + (icon.map { $0.size.width + 3 } ?? 0)) / 2
        if let icon {
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: bounds.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
            x += icon.size.width + 3
        }
        text.draw(at: NSPoint(x: x, y: bounds.midY - textSize.height / 2), withAttributes: attrs)
    }
}
