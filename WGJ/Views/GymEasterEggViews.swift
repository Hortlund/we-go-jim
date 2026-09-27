import SwiftUI

/// One short, silent animation; Reduce Motion keeps the plate stationary.
struct GymPlateAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        ZStack {
            Circle().fill(WGJTheme.accentGold.opacity(0.16))
            Circle().stroke(WGJTheme.accentGold, lineWidth: 3).padding(5)
            Circle().stroke(WGJTheme.accentGold.opacity(0.5), lineWidth: 2).padding(12)
            Circle().fill(WGJTheme.bgBase).frame(width: 10, height: 10)
        }
        .frame(width: 46, height: 46)
        .rotationEffect(.degrees(landed || reduceMotion ? 0 : -35))
        .offset(y: landed || reduceMotion ? 0 : -16)
        .opacity(landed || reduceMotion ? 1 : 0)
        .accessibilityHidden(true)
        .task {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { landed = true }
        }
    }
}

struct GymBroSettingsCard: View {
    @AppStorage(GymEasterEggPolicy.unlockedKey) private var unlocked = false
    @AppStorage(GymEasterEggPolicy.enabledKey) private var enabled = false
    @State private var taps = GymLogoTapProgress()
    @State private var showingReveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    if taps.tap() {
                        unlocked = true
                        showingReveal = true
                    }
                } label: {
                    Image("SplashIcon")
                        .resizable().scaledToFit().frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("We Go Jim logo")
                .accessibilityIdentifier("gym-secret-logo")
                VStack(alignment: .leading, spacing: 3) {
                    Text("We Go Jim").font(.headline)
                    Text("Made for showing up.").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if showingReveal {
                HStack(spacing: 12) {
                    GymPlateAnimation()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Brain empty. We go jim.").font(.headline)
                        Text("Gym-bro mode unlocked.").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .accessibilityIdentifier("gym-secret-reveal")
            }
            if unlocked {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gym-bro mode")
                        Text("More gym wisdom in your workout recaps.")
                            .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .tint(WGJTheme.accentGold)
                .accessibilityIdentifier("gym-bro-mode-toggle")
            }
        }
        .foregroundStyle(WGJTheme.textPrimary)
        .padding(14)
        .wgjCardContainer()
    }
}

struct GymCompletionEasterEgg: View {
    let egg: GymEasterEggPolicy.Completion

    var body: some View {
        HStack(spacing: 12) {
            if egg == .lightWeight { GymPlateAnimation() }
            else {
                Image(systemName: egg == .stairs || egg == .sitting ? "figure.stairs" : "dumbbell.fill")
                    .foregroundStyle(WGJTheme.accentGold).accessibilityHidden(true)
            }
            Text(egg.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
        .accessibilityIdentifier("gym-completion-easter-egg")
    }
}

struct GymWarmupSalute: View {
    let title: String
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { revealed.toggle() } label: {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(WGJTheme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gym-warmup-salute")
            if revealed {
                Text(GymEasterEggPolicy.warmupMessage)
                    .font(.caption).foregroundStyle(WGJTheme.accentGold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
