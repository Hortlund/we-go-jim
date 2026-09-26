import SwiftUI

struct CloudBackupProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let operation: CloudBackupOperation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(operation.title)
                    .font(.title2.bold())
                    .foregroundStyle(WGJTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if operation.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(operation.progress.stage.rawValue)
                            .font(.headline)
                        if let fraction = operation.progress.fraction {
                            ProgressView(value: fraction)
                                .tint(WGJTheme.accentBlue)
                                .accessibilityLabel(operation.progress.stage.rawValue)
                                .accessibilityValue(operation.progress.countDescription ?? "")
                        } else {
                            WGJActivityRunner(tint: WGJTheme.accentBlue)
                        }
                        if let counts = operation.progress.countDescription {
                            Text(counts).font(.subheadline.monospacedDigit())
                        }
                    }
                    .foregroundStyle(WGJTheme.textPrimary)

                    Text("Please keep WGJ open until this finishes. Large backups can take a few minutes.")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                } else {
                    Text(resultMessage)
                        .font(.body)
                        .foregroundStyle(WGJTheme.textSecondary)
                    Button("Done") { dismiss() }
                        .buttonStyle(WGJPrimaryButtonStyle())
                        .accessibilityIdentifier("cloud-backup-progress-done")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .background(WGJTheme.bgBase)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(operation.isRunning ? .hidden : .visible)
        .interactiveDismissDisabled(operation.isRunning)
        .accessibilityIdentifier("cloud-backup-progress-sheet")
    }

    private var symbol: String {
        switch operation.outcome {
        case .success: "checkmark.icloud.fill"
        case .failure: "exclamationmark.icloud.fill"
        case nil: operation.kind == .backup ? "icloud.and.arrow.up" : "icloud.and.arrow.down"
        }
    }

    private var tint: Color {
        switch operation.outcome {
        case .success: WGJTheme.success
        case .failure: WGJTheme.accentGold
        case nil: WGJTheme.accentBlue
        }
    }

    private var resultMessage: String {
        switch operation.outcome {
        case .success(let message), .failure(let message): message
        case nil: ""
        }
    }
}

/// Continuous activity, never a simulated completion percentage.
struct WGJActivityRunner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            GeometryReader { proxy in
                let width = proxy.size.width
                let runnerWidth = width * 0.28
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                Capsule().fill(tint.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: runnerWidth)
                            .offset(x: reduceMotion ? (width - runnerWidth) / 2 : (width + runnerWidth) * phase - runnerWidth)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In progress")
    }
}

#Preview("Restore progress") {
    let operation = CloudBackupOperation(kind: .restore, foreground: true)
    operation.update(.init(stage: .downloading, completed: 150, total: 420))
    return CloudBackupProgressSheet(operation: operation)
}
