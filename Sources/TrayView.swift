import SwiftUI

struct TrayView: View {
    @ObservedObject var manager: TunnelManager
    @State private var presets: [TunnelPreset] = []
    
    // Состояния экранов для inline-навигации
    enum Screen: Equatable {
        case main
        case add
        case edit(TunnelPreset)
    }
    @State private var currentScreen: Screen = .main
    @State private var isHoveringPlus = false
    
    init(manager: TunnelManager) {
        self.manager = manager
        if let data = UserDefaults.standard.data(forKey: "tunnel_presets"),
           let decoded = try? JSONDecoder().decode([TunnelPreset].self, from: data) {
            _presets = State(initialValue: decoded)
        } else {
            // Пресеты по умолчанию
            _presets = State(initialValue: [
                TunnelPreset(name: "Next.js Frontend", port: 3000),
                TunnelPreset(name: "FastAPI Backend", port: 8000)
            ])
        }
    }
    
    var body: some View {
        VStack {
            switch currentScreen {
            case .main:
                mainScreenView
            case .add:
                AddPresetView(
                    onAdd: { newPreset in
                        presets.append(newPreset)
                        savePresets()
                        currentScreen = .main
                    },
                    onCancel: {
                        currentScreen = .main
                    }
                )
            case .edit(let preset):
                EditPresetView(
                    preset: preset,
                    onSave: { updatedPreset in
                        if let index = presets.firstIndex(where: { $0.id == updatedPreset.id }) {
                            presets[index] = updatedPreset
                            savePresets()
                            
                            // Перезапуск туннеля, если он активен
                            if let state = manager.tunnelStates[updatedPreset.id],
                               (state == .connecting || isStateActive(state)) {
                                manager.startTunnel(preset: updatedPreset)
                            }
                        }
                        currentScreen = .main
                    },
                    onDelete: {
                        deletePreset(preset)
                        currentScreen = .main
                    },
                    onCancel: {
                        currentScreen = .main
                    }
                )
            }
        }
        .padding(12)
        .frame(width: 350)
    }
    
    private func isStateActive(_ state: TunnelState) -> Bool {
        if case .active = state { return true }
        return false
    }
    
    // Представление главного экрана
    private var mainScreenView: some View {
        VStack(spacing: 12) {
            statusHeader
            
            Divider()
            
            presetsSection
            
            Divider()
            
            footerSection
        }
    }
    
    private var statusHeader: some View {
        HStack {
            Circle()
                .fill(manager.isAnyTunnelActive ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(manager.isAnyTunnelActive ? "Tunnelhunt запущен" : "Туннели выключены")
                .font(.system(size: 13, weight: .bold))
            
            Spacer()
        }
    }
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Пресеты")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Добавление пресета как элемент с onTapGesture, чтобы не закрывать меню
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(isHoveringPlus ? .primary : .secondary)
                    .font(.system(size: 14))
                    .help("Добавить новый пресет")
                    .onTapGesture {
                        currentScreen = .add
                    }
                    .onHover { hovering in
                        isHoveringPlus = hovering
                    }
            }
            
            if presets.isEmpty {
                Text("Пресеты не настроены. Нажмите +, чтобы добавить.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(presets) { preset in
                            presetRow(for: preset)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }
    
    private func presetRow(for preset: TunnelPreset) -> some View {
        let state = manager.tunnelStates[preset.id] ?? .inactive
        return PresetRowView(
            preset: preset,
            state: state,
            onToggle: { newValue in
                if newValue {
                    manager.startTunnel(preset: preset)
                } else {
                    manager.stopTunnel(for: preset.id)
                }
            },
            onEdit: {
                currentScreen = .edit(preset)
            }
        )
    }
    
    private func deletePreset(_ preset: TunnelPreset) {
        manager.stopTunnel(for: preset.id)
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets.remove(at: index)
            savePresets()
        }
    }
    
    private var footerSection: some View {
        HStack {
            Button("Остановить все") {
                manager.stopAllTunnels()
            }
            .buttonStyle(.bordered)
            .disabled(!manager.isAnyTunnelActive)
            
            Spacer()
            
            // Выход через onTapGesture для предотвращения автозакрытия, если нужно
            Text("Выйти")
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .onTapGesture {
                    manager.stopAllTunnels()
                    NSApplication.shared.terminate(nil)
                }
        }
    }
    
    private func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: "tunnel_presets")
        }
    }
}

// Отдельное представление для строки пресета
struct PresetRowView: View {
    var preset: TunnelPreset
    var state: TunnelState
    var onToggle: (Bool) -> Void
    var onEdit: () -> Void
    
    @State private var isHovering = false
    @State private var isCopied = false
    
    // Цветовая метка иконки в зависимости от состояния
    private var iconColor: Color {
        switch state {
        case .inactive: return .secondary
        case .connecting: return .orange
        case .active: return .green
        case .error: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                // Отображение статусов подключения и ошибок
                switch state {
                case .inactive:
                    HStack(spacing: 6) {
                        Text("Порт: \(String(preset.port))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        if let keyPath = preset.sshKeyPath, !keyPath.isEmpty {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                            Text(URL(fileURLWithPath: keyPath).lastPathComponent)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                case .connecting:
                    Text("Подключение...")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .italic()
                case .active(let url):
                    Text(url)
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                case .error(let message):
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .help(message)
                }
            }
            
            Spacer()
            
            if case .active(let url) = state {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(isHovering ? (isCopied ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1)) : Color.clear)
                    .cornerRadius(4)
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        withAnimation {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    }
                    .help(isCopied ? "Скопировано!" : "Скопировать ссылку")
            }
            
            // Кнопка редактирования на onTapGesture
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
                .cornerRadius(4)
                .onTapGesture {
                    onEdit()
                }
                .help("Редактировать пресет")
            
            Toggle("", isOn: Binding(
                get: {
                    switch state {
                    case .connecting, .active: return true
                    default: return false
                    }
                },
                set: onToggle
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .frame(width: 38)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
