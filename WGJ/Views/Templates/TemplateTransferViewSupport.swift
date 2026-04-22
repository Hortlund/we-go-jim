import Foundation

enum TemplateTransferShareTarget: Equatable, Sendable {
    case template(UUID)
    case folder(UUID)
}

struct TemplateTransferExportRequest: Identifiable, Equatable {
    let id = UUID()
    let target: TemplateTransferShareTarget
}

struct TemplateTransferShareSheetItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}
