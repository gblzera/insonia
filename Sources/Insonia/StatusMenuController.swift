import AppKit
import ServiceManagement
import IOKit.ps

/// Constrói o ícone do menu bar e o menu dinâmico.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pm = PowerManager.shared

    /// Modo escolhido para as próximas ativações (tela vs sistema).
    private var preferredMode: KeepAwakeMode = .display

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu

        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        pm.onChange = { [weak self] in
            if Thread.isMainThread { self?.refresh() }
            else { DispatchQueue.main.async { self?.refresh() } }
        }
        refresh()
    }

    // MARK: - Ícone do menu bar

    private func refresh() {
        guard let button = statusItem.button else { return }
        let symbol = pm.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Insônia")
        img?.isTemplate = true
        button.image = img

        if pm.isActive, let r = pm.remaining {
            button.title = " " + Self.compact(r)
        } else {
            button.title = ""
        }
    }

    /// Tempo pro menu bar: "0:45" no último minuto, senão "45m" / "1h05".
    private static func compact(_ s: TimeInterval) -> String {
        let total = max(0, Int(s.rounded()))
        if total < 60 {
            return String(format: "0:%02d", total)   // conta os segundos no fim
        }
        let m = (total + 59) / 60                      // arredonda pra cima, em minutos
        if m >= 60 {
            return "\(m / 60)h\(String(format: "%02d", m % 60))"
        }
        return "\(m)m"
    }

    // MARK: - Construção do menu (NSMenuDelegate)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Cabeçalho de status (desabilitado, só informativo).
        let header: String
        if pm.isActive {
            if let end = pm.endDate {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                header = "● Ativo · \(pm.mode.label) · até \(f.string(from: end))"
            } else {
                header = "● Ativo · \(pm.mode.label) · sem limite"
            }
        } else {
            header = "○ Desativado"
        }
        addDisabled(menu, header)
        if pm.isActive && onBattery() {
            addDisabled(menu, "⚠︎ na bateria — isto consome a carga")
        }
        menu.addItem(.separator())

        // Durações.
        addAction(menu, "Sem limite", #selector(activateDuration(_:)),
                  value: -1, checked: pm.isActive && pm.endDate == nil)
        addAction(menu, "15 minutos", #selector(activateDuration(_:)), value: 15 * 60)
        addAction(menu, "30 minutos", #selector(activateDuration(_:)), value: 30 * 60)
        addAction(menu, "1 hora", #selector(activateDuration(_:)), value: 60 * 60)
        addAction(menu, "2 horas", #selector(activateDuration(_:)), value: 120 * 60)

        // Até hora X.
        let until = NSMenu()
        for h in [17, 18, 19, 20, 22, 0] {
            let title = h == 0 ? "Meia-noite" : String(format: "Até %02d:00", h)
            let it = NSMenuItem(title: title, action: #selector(activateUntil(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = NSNumber(value: h)
            until.addItem(it)
        }
        let untilItem = NSMenuItem(title: "Até…", action: nil, keyEquivalent: "")
        untilItem.submenu = until
        menu.addItem(untilItem)

        menu.addItem(.separator())

        // Modo.
        addDisabled(menu, "Modo")
        addMode(menu, "Manter a tela ligada", .display)
        addMode(menu, "Manter só o sistema (tela pode apagar)", .system)

        menu.addItem(.separator())

        // Atalhos nomeados.
        addDisabled(menu, "Atalhos")
        addPreset(menu, "Reunião — 1h, tela ligada", index: 0)
        addPreset(menu, "Apresentação — sem limite, tela ligada", index: 1)
        addPreset(menu, "Modelo rodando — sem limite, só sistema", index: 2)

        menu.addItem(.separator())

        if pm.isActive {
            let off = NSMenuItem(title: "Desativar", action: #selector(deactivate(_:)), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        }

        let login = NSMenuItem(title: "Abrir no login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = isLoginEnabled() ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Sair", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Helpers de construção

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        menu.addItem(it)
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ sel: Selector,
                           value: Double, checked: Bool = false) {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.representedObject = NSNumber(value: value)
        it.state = checked ? .on : .off
        menu.addItem(it)
    }

    private func addMode(_ menu: NSMenu, _ title: String, _ m: KeepAwakeMode) {
        let it = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = NSNumber(value: m.rawValue)
        let current = pm.isActive ? pm.mode : preferredMode
        it.state = current == m ? .on : .off
        menu.addItem(it)
    }

    private func addPreset(_ menu: NSMenu, _ title: String, index: Int) {
        let it = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
        it.target = self
        it.representedObject = NSNumber(value: index)
        menu.addItem(it)
    }

    // MARK: - Ações

    @objc private func activateDuration(_ sender: NSMenuItem) {
        let v = (sender.representedObject as? NSNumber)?.doubleValue ?? -1
        let duration: TimeInterval? = v < 0 ? nil : v
        pm.activate(mode: preferredMode, duration: duration)
    }

    @objc private func activateUntil(_ sender: NSMenuItem) {
        guard let h = (sender.representedObject as? NSNumber)?.intValue else { return }
        let target = dateForHour(h)
        pm.activate(mode: preferredMode, duration: target.timeIntervalSinceNow)
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = (sender.representedObject as? NSNumber)?.intValue,
              let m = KeepAwakeMode(rawValue: raw) else { return }
        preferredMode = m
        guard pm.isActive else { return }
        // Reaplica preservando o estado da sessão atual:
        if pm.endDate == nil {
            pm.activate(mode: m, duration: nil)          // sem limite continua sem limite
        } else if let r = pm.remaining, r > 0 {
            pm.activate(mode: m, duration: r)            // mantém o tempo restante
        } else {
            pm.deactivate()                              // já estava expirando: desliga
        }
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let idx = (sender.representedObject as? NSNumber)?.intValue else { return }
        switch idx {
        case 0: preferredMode = .display; pm.activate(mode: .display, duration: 60 * 60)
        case 1: preferredMode = .display; pm.activate(mode: .display, duration: nil)
        case 2: preferredMode = .system;  pm.activate(mode: .system, duration: nil)
        default: break
        }
    }

    @objc private func deactivate(_ sender: NSMenuItem) {
        pm.deactivate()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        pm.deactivate()
        NSApp.terminate(nil)
    }

    // MARK: - Abrir no login (macOS 13+)

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
            } else {
                try svc.register()
                // Recém-registrado costuma ficar "aguardando aprovação":
                // leva o usuário direto pros Ajustes do Sistema.
                if svc.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            showLoginError(error)
        }
    }

    @available(macOS 13.0, *)
    private func showLoginError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Não consegui ligar o “Abrir no login”."
        let inApps = Bundle.main.bundlePath.hasPrefix("/Applications/")
        alert.informativeText = inApps
            ? "O macOS pediu aprovação. Confira em Ajustes do Sistema › Geral › Itens de Início.\n\n(\(error.localizedDescription))"
            : "Mova o Insônia para a pasta Aplicativos e tente de novo — o login automático precisa de um local fixo.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func isLoginEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    /// Está rodando na bateria (e não na tomada)?
    private func onBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }

    /// Próxima ocorrência de `hour:00` (hoje, ou amanhã se já passou).
    private func dateForHour(_ hour: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = ((hour % 24) + 24) % 24
        comps.minute = 0
        comps.second = 0
        var target = cal.date(from: comps) ?? now.addingTimeInterval(3600)
        if target <= now {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86400)
        }
        return target
    }
}
