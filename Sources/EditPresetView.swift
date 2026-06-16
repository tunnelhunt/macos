import SwiftUI
import AppKit

struct EditPresetView: View {
    var preset: TunnelPreset
    var onSave: (TunnelPreset) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void
    
    @State private var name: String
    @State private var portString: String
    @State private var sshKeyPath: String
    
    init(preset: TunnelPreset, onSave: @escaping (TunnelPreset) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.preset = preset
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: preset.name)
        _portString = State(initialValue: String(preset.port))
        _sshKeyPath = State(initialValue: preset.sshKeyPath ?? "")
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Навигационная панель сверху
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Назад")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Пресет")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                // Пустая заглушка для выравнивания
                Spacer().frame(width: 50)
            }
            .padding(.bottom, 6)
            
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Название пресета")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    TextField("например, Frontend Dev", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Локальный порт")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    TextField("например, 8080", text: $portString)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Приватный SSH-ключ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("Использовать системный ключ по умолчанию", text: $sshKeyPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                            .font(.system(size: 11))
                        
                        Button("Обзор...") {
                            selectSSHKey()
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                    }
                }
            }
            
            Spacer().frame(height: 10)
            
            HStack {
                Button(action: {
                    onDelete()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Удалить")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Сохранить") {
                    if let port = Int(portString), !name.isEmpty {
                        var updated = preset
                        updated.name = name
                        updated.port = port
                        updated.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
                        onSave(updated)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || Int(portString) == nil)
            }
        }
        .padding(12)
        .frame(width: 350, height: 260)
    }
    
    private func selectSSHKey() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Выберите приватный SSH-ключ"
        openPanel.showsHiddenFiles = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sshDir = homeDir.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) {
            openPanel.directoryURL = sshDir
        } else {
            openPanel.directoryURL = homeDir
        }
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    self.sshKeyPath = url.path
                }
            }
        }
    }
}
