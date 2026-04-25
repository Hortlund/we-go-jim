import SwiftUI

struct WGJResponsiveTextDraft: Equatable {
    private(set) var liveText: String
    private(set) var committedText: String

    init(committedText: String = "") {
        self.liveText = committedText
        self.committedText = committedText
    }

    var hasUncommittedChanges: Bool {
        liveText != committedText
    }

    mutating func stageLiveText(_ text: String) {
        liveText = text
    }

    mutating func syncCommittedText(_ text: String) {
        let wasDirty = hasUncommittedChanges
        committedText = text
        if !wasDirty {
            liveText = text
        }
    }

    mutating func commitLiveText() -> String? {
        guard liveText != committedText else { return nil }
        committedText = liveText
        return liveText
    }
}

struct WGJResponsiveTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis?
    var lineLimit: ClosedRange<Int>?
    var capitalization: TextInputAutocapitalization?
    var keyboardType: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .done
    var autocorrectionDisabled = false
    var accessibilityIdentifier: String?
    var commitDelay: Duration = .milliseconds(140)
    var onSubmit: (() -> Void)?

    @State private var draft = WGJResponsiveTextDraft()
    @FocusState private var isFocused: Bool

    var body: some View {
        textField
            .focused($isFocused)
            .keyboardType(keyboardType)
            .submitLabel(submitLabel)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(autocorrectionDisabled)
            .wgjPillField()
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
            .onAppear {
                draft = WGJResponsiveTextDraft(committedText: text)
            }
            .onChange(of: text) { _, newValue in
                draft.syncCommittedText(newValue)
            }
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                commitNow()
            }
            .onDisappear {
                commitNow()
            }
    }

    @ViewBuilder
    private var textField: some View {
        if let axis {
            if let lineLimit {
                TextField(
                    placeholder,
                    text: liveTextBinding,
                    axis: axis
                )
                .lineLimit(lineLimit)
                .onSubmit {
                    commitNow()
                    onSubmit?()
                }
            } else {
                TextField(
                    placeholder,
                    text: liveTextBinding,
                    axis: axis
                )
                .onSubmit {
                    commitNow()
                    onSubmit?()
                }
            }
        } else {
            TextField(
                placeholder,
                text: liveTextBinding
            )
            .onSubmit {
                commitNow()
                onSubmit?()
            }
        }
    }

    private var liveTextBinding: Binding<String> {
        Binding(
            get: { draft.liveText },
            set: { newValue in
                draft.stageLiveText(newValue)
            }
        )
    }

    private func commitNow() {
        guard let committed = draft.commitLiveText() else { return }
        text = committed
    }
}
