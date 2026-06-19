import Foundation
import Combine
import Cocoa
import UserNotifications

enum TunnelState: Equatable {
    case inactive
    case connecting
    case active(url: String)
    case error(message: String)
}

class TunnelManager: ObservableObject {
    // Состояние каждого туннеля по UUID пресета
    @Published var tunnelStates: [UUID: TunnelState] = [:]
    
    // Хранение запущенных процессов по UUID пресета
    private var processes: [UUID: Process] = [:]
    private var outputPipes: [UUID: Pipe] = [:]
    private var errorPipes: [UUID: Pipe] = [:]
    
    // Накопленный вывод для каждого пресета
    private var accumulatedOutput: [UUID: String] = [:]
    
    // Хранение последней ошибки из stderr для каждого пресета
    private var lastErrorMessages: [UUID: String] = [:]
    
    // Реконнекты
    private var reconnectAttempts: [UUID: Int] = [:]
    private var lifetimeLimitReached: [UUID: Bool] = [:]
    private var closedFromDashboard: [UUID: Bool] = [:]
    private var lastPresets: [UUID: TunnelPreset] = [:]
    
    // Таймеры таймаута подключения
    private var timeoutTimers: [UUID: Timer] = [:]
    
    var isAnyTunnelActive: Bool {
        return tunnelStates.values.contains { state in
            if case .active = state { return true }
            if case .connecting = state { return true }
            return false
        }
    }
    
    var activeTunnelsCount: Int {
        return tunnelStates.values.filter { state in
            if case .active = state { return true }
            return false
        }.count
    }
    
    #if DEBUG
    static let defaultHost = ProcessInfo.processInfo.environment["TUNNELHUNT_HOST"] ?? "localhost"
    static let defaultPort = Int(ProcessInfo.processInfo.environment["TUNNELHUNT_PORT"] ?? "") ?? 2222
    #else
    static let defaultHost = ProcessInfo.processInfo.environment["TUNNELHUNT_HOST"] ?? "tunnelhunt.ru"
    static let defaultPort = Int(ProcessInfo.processInfo.environment["TUNNELHUNT_PORT"] ?? "") ?? 2222
    #endif
    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[Tunnelhunt] [\(timestamp)] \(message)")
    }
    
    init() {
        // Запрос разрешения на отправку уведомлений (только если упаковано в App Bundle)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        #if DEBUG
        let buildMode = "DEBUG"
        #else
        let buildMode = "RELEASE"
        #endif
        log("Инициализация TunnelManager. Режим сборки: \(buildMode). Хост по умолчанию: \(TunnelManager.defaultHost), Порт: \(TunnelManager.defaultPort)")
    }
    
    func startTunnel(preset: TunnelPreset, host: String = TunnelManager.defaultHost, sshPort: Int = TunnelManager.defaultPort, isReconnect: Bool = false) {
        let presetId = preset.id
        
        if !isReconnect {
            reconnectAttempts[presetId] = 0
            lifetimeLimitReached[presetId] = false
            closedFromDashboard[presetId] = false
        }
        lastPresets[presetId] = preset
        
        stopTunnel(for: presetId, resetState: false)
        
        log("[\(preset.name)] Запуск туннеля для порта \(preset.port) на хост \(host):\(sshPort)...")
        
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var arguments = [
            "-tt", // Force pseudo-terminal allocation to disable stdout buffering
            "-p", String(sshPort),
            // Автоматически принимать ключ хоста при первом подключении
            "-o", "StrictHostKeyChecking=accept-new",
            // Отключаем интерактивные запросы ввода, чтобы избежать бесконечного зависания
            "-o", "BatchMode=yes"
        ]
        
        #if DEBUG
        arguments.append("-v")
        #endif
        
        // Добавляем флаг -i, если указан путь к ключу
        if let keyPath = preset.sshKeyPath, !keyPath.isEmpty {
            arguments.append(contentsOf: ["-i", keyPath])
            log("[\(preset.name)] Использование SSH-ключа: \(keyPath)")
        }
        
        // Настройка реверсивного туннеля (порт 80 на удаленном сервере перенаправляет на localhost:порт)
        arguments.append(contentsOf: ["-R", "80:localhost:\(preset.port)", host])
        newProcess.arguments = arguments
        
        log("[\(preset.name)] Запускаем команду: ssh \(arguments.joined(separator: " "))")
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe
        newProcess.standardInput = stdinPipe
        
        self.processes[presetId] = newProcess
        self.outputPipes[presetId] = stdoutPipe
        self.errorPipes[presetId] = stderrPipe
        
        // Сбрасываем накопленный лог ошибок
        self.lastErrorMessages[presetId] = nil
        self.accumulatedOutput[presetId] = ""
        
        // Устанавливаем статус подключения
        self.tunnelStates[presetId] = .connecting
        
        // Чтение stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            let output = String(decoding: data, as: UTF8.self)
            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanOutput.isEmpty {
                self?.log("[\(preset.name)] SSH STDOUT (\(data.count) bytes): \(cleanOutput)")
            } else {
                self?.log("[\(preset.name)] SSH STDOUT: received \(data.count) bytes of whitespace")
            }
            self?.appendOutput(output, for: presetId, presetName: preset.name)
        }
        
        // Чтение stderr для отслеживания ошибок подключения
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            let errorOutput = String(decoding: data, as: UTF8.self)
            let cleanMsg = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanMsg.isEmpty {
                self?.log("[\(preset.name)] SSH STDERR: \(cleanMsg)")
                // Запоминаем последнюю значимую строчку из stderr
                self?.lastErrorMessages[presetId] = cleanMsg
            }
        }
        
        // Запуск таймера таймаута на 8 секунд
        let timer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.tunnelStates[presetId] == .connecting {
                    self?.log("[\(preset.name)] Таймаут подключения (8с) превышен. Останавливаем процесс...")
                    self?.stopTunnel(for: presetId, resetState: false)
                    self?.tunnelStates[presetId] = .error(message: "Таймаут подключения (8с)")
                }
            }
        }
        self.timeoutTimers[presetId] = timer
        
        newProcess.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleTermination(for: presetId, status: process.terminationStatus)
            }
        }
        
        do {
            try newProcess.run()
            log("[\(preset.name)] Процесс SSH успешно запущен.")
        } catch {
            log("[\(preset.name)] Не удалось запустить SSH процесс: \(error.localizedDescription)")
            self.tunnelStates[presetId] = .error(message: "Ошибка запуска: \(error.localizedDescription)")
            handleTermination(for: presetId, status: -1)
        }
    }
    
    func stopTunnel(for presetId: UUID, resetState: Bool = true) {
        // Сброс таймера
        timeoutTimers[presetId]?.invalidate()
        timeoutTimers.removeValue(forKey: presetId)
        
        if let process = processes[presetId] {
            log("[\(presetId)] Запрос остановки туннеля...")
            if process.isRunning {
                process.terminate()
                log("[\(presetId)] Процесс SSH завершен принудительно.")
            }
        }
        
        self.processes.removeValue(forKey: presetId)
        self.outputPipes[presetId]?.fileHandleForReading.readabilityHandler = nil
        self.outputPipes.removeValue(forKey: presetId)
        self.errorPipes[presetId]?.fileHandleForReading.readabilityHandler = nil
        self.errorPipes.removeValue(forKey: presetId)
        self.accumulatedOutput.removeValue(forKey: presetId)
        
        if resetState {
            self.tunnelStates[presetId] = .inactive
        }
    }
    
    func stopAllTunnels() {
        log("Останавливаем все активные туннели...")
        let keys = Array(processes.keys)
        for presetId in keys {
            stopTunnel(for: presetId)
        }
    }
    
    private func appendOutput(_ text: String, for presetId: UUID, presetName: String) {
        DispatchQueue.main.async {
            let current = self.accumulatedOutput[presetId] ?? ""
            let updated = current + text
            self.accumulatedOutput[presetId] = updated
            self.parseOutput(updated, for: presetId, presetName: presetName)
        }
    }
    
    private func parseOutput(_ text: String, for presetId: UUID, presetName: String) {
        if text.contains("[Limit]") || text.contains("lifetime limit reached") {
            self.lifetimeLimitReached[presetId] = true
        }
        if text.contains("[Closed]") || text.contains("Tunnel closed from dashboard") {
            self.closedFromDashboard[presetId] = true
        }
        
        // Поддерживаем как .ru, так и любой локальный домен для тестирования
        let pattern = "https://[a-zA-Z0-9.-]+\\.[a-zA-Z0-9.-]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        
        if let firstMatch = results.first {
            let url = nsString.substring(with: firstMatch.range)
            
            // Отменяем таймер таймаута
            timeoutTimers[presetId]?.invalidate()
            timeoutTimers.removeValue(forKey: presetId)
            
            // Сбрасываем накопленные ошибки, так как подключение прошло успешно
            lastErrorMessages[presetId] = nil
            
            if self.tunnelStates[presetId] != .active(url: url) {
                self.log("[\(presetName)] Найден URL туннеля: \(url).")
                self.tunnelStates[presetId] = .active(url: url)
                
                self.showNotification(
                    title: "Туннель \"\(presetName)\" запущен",
                    body: "Ссылка: \(url)"
                )
            }
        }
    }
    
    private func handleTermination(for presetId: UUID, status: Int32) {
        log("[\(presetId)] Завершение процесса SSH с кодом: \(status)")
        
        let wasStoppedManually = (self.processes[presetId] == nil)
        
        timeoutTimers[presetId]?.invalidate()
        timeoutTimers.removeValue(forKey: presetId)
        
        self.processes.removeValue(forKey: presetId)
        self.outputPipes[presetId]?.fileHandleForReading.readabilityHandler = nil
        self.outputPipes.removeValue(forKey: presetId)
        self.errorPipes[presetId]?.fileHandleForReading.readabilityHandler = nil
        self.errorPipes.removeValue(forKey: presetId)
        self.accumulatedOutput.removeValue(forKey: presetId)
        
        if wasStoppedManually {
            log("[\(presetId)] Процесс был остановлен вручную, игнорируем ошибку завершения.")
            return
        }
        
        // Если процесс завершился с ошибкой (ненулевой статус)
        if status != 0 {
            if self.lifetimeLimitReached[presetId] == true {
                self.tunnelStates[presetId] = .error(message: "Отключено по таймауту для бесплатных тарифов")
                return
            }
            if self.closedFromDashboard[presetId] == true {
                self.tunnelStates[presetId] = .error(message: "Туннель отключен через дашборд")
                return
            }
            
            let attempts = self.reconnectAttempts[presetId] ?? 0
            if attempts < 5 {
                self.reconnectAttempts[presetId] = attempts + 1
                log("[\(presetId)] Неожиданное отключение. Попытка переподключения \(attempts + 1)/5...")
                
                if let preset = self.lastPresets[presetId] {
                    self.showNotification(
                        title: "Туннель \"\(preset.name)\" упал",
                        body: "Пытаемся переподключиться (\(attempts + 1)/5)..."
                    )
                    
                    self.tunnelStates[presetId] = .connecting
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        // Только если он все еще в статусе connecting (не был остановлен вручную)
                        if self?.tunnelStates[presetId] == .connecting {
                            self?.startTunnel(preset: preset, isReconnect: true)
                        }
                    }
                }
                return
            }
            
            // Если все попытки исчерпаны
            var errorMsg = lastErrorMessages[presetId] ?? "Соединение с сервером разорвано (код \(status))"
            if errorMsg.contains("Pseudo-terminal will not be allocated") {
                errorMsg = "Ошибка подключения (проверьте порт SSH/сервер)"
            }
            log("[\(presetId)] Ошибка туннеля: \(errorMsg)")
            self.tunnelStates[presetId] = .error(message: errorMsg)
        } else {
            if self.closedFromDashboard[presetId] == true {
                self.tunnelStates[presetId] = .error(message: "Туннель отключен через дашборд")
            } else {
                self.tunnelStates[presetId] = .inactive
            }
        }
    }
    
    private func showNotification(title: String, body: String) {
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Failed to add notification: \(error.localizedDescription)")
                }
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
            process.arguments = ["-e", "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""]
            try? process.run()
        }
    }
}
