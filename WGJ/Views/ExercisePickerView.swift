import SwiftData
import SwiftUI
import UIKit

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let actionTitle: String
    let onSelect: (ExerciseCatalogSelection) -> ExercisePickerSelectionResult

    @State private var duplicateNotice: ExerciseSelectionDuplicateNotice?
    @State private var duplicateNoticeClearTask: Task<Void, Never>?

    init(
        title: String = "Add Exercise",
        actionTitle: String? = nil,
        onSelect: @escaping (ExerciseCatalogSelection) -> ExercisePickerSelectionResult
    ) {
        self.title = title
        self.actionTitle = actionTitle ?? title
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ExercisesCatalogView(mode: .pick(actionTitle: actionTitle, onSelect: { selected in
                handleSelection(selected)
            }))
            .wgjNavigationChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        WGJKeyboard.dismiss()
                        dismiss()
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let duplicateNotice {
                WGJTransientBanner(
                    title: duplicateNotice.title,
                    message: duplicateNotice.message,
                    icon: "exclamationmark.circle.fill",
                    tint: WGJTheme.warning
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityIdentifier("exercise-picker-duplicate-warning")
            }
        }
        .onDisappear {
            duplicateNoticeClearTask?.cancel()
            duplicateNoticeClearTask = nil
        }
    }

    private func handleSelection(_ selected: ExerciseCatalogSelection) {
        WGJKeyboard.dismiss()

        let result = onSelect(selected)
        guard !result.shouldDismissPicker else {
            dismiss()
            return
        }

        guard let notice = result.notice else { return }
        showDuplicateNotice(notice)
    }

    private func showDuplicateNotice(_ notice: ExerciseSelectionDuplicateNotice) {
        duplicateNoticeClearTask?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            duplicateNotice = notice
        }

        duplicateNoticeClearTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await self.clearDuplicateNoticeAfterDelayIfStillNeeded()
        }
    }

    @MainActor
    private func clearDuplicateNoticeAfterDelayIfStillNeeded() {
        guard !Task.isCancelled else { return }
        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            duplicateNotice = nil
        }
        duplicateNoticeClearTask = nil
    }
}
