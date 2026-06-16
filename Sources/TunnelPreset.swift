import Foundation

struct TunnelPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var port: Int
    var sshKeyPath: String?
    var customSubdomain: String?
}
