import Foundation
import IOKit.pwr_mgt
import AppKit

/// O que exatamente queremos manter acordado.
enum KeepAwakeMode: Int {
    /// Mantém a TELA ligada (apresentação, demo, dashboard).
    case display = 0
    /// Mantém só o SISTEMA acordado — a tela pode apagar (modelo rodando à noite).
    case system = 1

    var assertionType: String {
        switch self {
        case .display: return kIOPMAssertionTypePreventUserIdleDisplaySleep
        case .system:  return kIOPMAssertionTypePreventUserIdleSystemSleep
        }
    }

    var label: String {
        switch self {
        case .display: return "tela ligada"
        case .system:  return "só o sistema"
        }
    }
}

/// Núcleo: cria/solta a IOKit power assertion e cuida do timer de duração.
final class PowerManager {
    static let shared = PowerManager()

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var hasAssertion = false
    private var ticker: Timer?

    private(set) var isActive = false
    private(set) var mode: KeepAwakeMode = .display
    private(set) var endDate: Date?   // nil = sem limite

    /// Chamado (na main thread) sempre que o estado muda — a UI se atualiza por aqui.
    var onChange: (() -> Void)?

    private init() {
        // Ao acordar do sleep o Timer pode ter "congelado"; reavalia na hora
        // pra não soltar a assertion (e beepar) num horário aleatório depois.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    /// Segundos restantes, ou nil se inativo / sem limite.
    var remaining: TimeInterval? {
        guard isActive, let endDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    /// Ativa o "anti-soneca". `duration` em segundos; nil = sem limite.
    func activate(mode: KeepAwakeMode, duration: TimeInterval?) {
        // Duração explícita já esgotada (ex.: trocar de modo no último segundo
        // de uma sessão temporizada): isso é um TÉRMINO, não "sem limite".
        if let duration, duration <= 0 {
            deactivate()
            return
        }

        releaseAssertion()
        self.mode = mode

        let reason = "Insônia — mantendo o Mac acordado" as CFString
        let type = mode.assertionType as CFString
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            // Não conseguiu criar a assertion: volta tudo ao estado inativo.
            isActive = false
            hasAssertion = false
            endDate = nil
            stopTicker()
            onChange?()
            return
        }

        hasAssertion = true
        isActive = true
        if let duration {          // aqui já é garantidamente > 0
            endDate = Date().addingTimeInterval(duration)
        } else {
            endDate = nil           // sem limite
        }
        startTicker()
        onChange?()
    }

    /// Desliga e solta a assertion.
    func deactivate() {
        releaseAssertion()
        stopTicker()
        isActive = false
        endDate = nil
        onChange?()
    }

    private func releaseAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
            hasAssertion = false
        }
    }

    /// Ao acordar do sleep: se o prazo venceu durante o sono, desliga já —
    /// em vez de esperar o próximo tick e beepar com atraso.
    private func handleWake() {
        guard isActive else { return }
        if let end = endDate, Date() >= end {
            deactivate()
            NSSound.beep()
        } else {
            onChange?()
        }
    }

    /// Um único timer de 1s: atualiza a contagem e desliga quando chega a hora.
    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isActive else { return }
            if let end = self.endDate, Date() >= end {
                self.deactivate()
                NSSound.beep()
                return
            }
            self.onChange?()
        }
        // .common para o contador continuar mexendo com o menu aberto.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
