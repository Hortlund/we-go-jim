import SwiftUI
import UIKit

/// Submit each burst once; the render server plays it without a SwiftUI frame timer.
struct WorkoutCompletionConfettiLayerView: UIViewRepresentable {
    let origin: CGPoint
    let pieces: [WorkoutCompletionConfettiPiece]
    let startDate: Date

    func makeUIView(context: Context) -> WorkoutCompletionConfettiUIView {
        WorkoutCompletionConfettiUIView()
    }

    func updateUIView(_ view: WorkoutCompletionConfettiUIView, context: Context) {
        view.configure(origin: origin, pieces: pieces, startDate: startDate)
    }
}

final class WorkoutCompletionConfettiUIView: UIView {
    private var origin = CGPoint.zero
    private var pieces: [WorkoutCompletionConfettiPiece] = []
    private var startDate: Date?
    private var renderedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(origin: CGPoint, pieces: [WorkoutCompletionConfettiPiece], startDate: Date) {
        guard self.startDate != startDate || self.origin != origin else { return }
        self.origin = origin
        self.pieces = pieces
        self.startDate = startDate
        renderedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, renderedSize != bounds.size,
              let startDate else { return }
        renderedSize = bounds.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let elapsed = Date.now.timeIntervalSince(startDate)
        let burstStart = layer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        for piece in pieces where elapsed < piece.delay + piece.duration {
            let particle = CALayer()
            particle.bounds = CGRect(x: 0, y: 0, width: piece.width, height: piece.height)
            particle.cornerRadius = piece.cornerRadius
            particle.backgroundColor = UIColor(piece.color).resolvedColor(with: traitCollection).cgColor
            particle.opacity = 0
            layer.addSublayer(particle)
            particle.add(
                Self.animation(for: piece, origin: origin, size: bounds.size, beginTime: burstStart + piece.delay),
                forKey: "confetti"
            )
        }
    }

    static func animation(
        for piece: WorkoutCompletionConfettiPiece,
        origin: CGPoint,
        size: CGSize,
        beginTime: CFTimeInterval
    ) -> CAAnimationGroup {
        let spreadX = WorkoutCompletionConfettiPolicy.initialSpreadX(for: size.width)
        let spreadY = WorkoutCompletionConfettiPolicy.initialSpreadY(for: size.height)
        let scaleX = WorkoutCompletionConfettiPolicy.horizontalMotionScale(for: size.width)
        let scaleY = WorkoutCompletionConfettiPolicy.verticalMotionScale(for: size.height)
        let position = CAKeyframeAnimation(keyPath: "position")
        // Interpolate the existing trajectory; no per-frame path construction or color resolution.
        position.values = (0...120).map { index in
            let progress = Double(index) / 120
            return NSValue(cgPoint: CGPoint(
                x: origin.x + piece.originX * spreadX + piece.xOffset(progress: progress) * scaleX,
                y: origin.y + piece.originY * spreadY + piece.yOffset(progress: progress) * scaleY
            ))
        }
        position.calculationMode = .linear

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = piece.rotation(progress: 0) * .pi / 180
        rotation.toValue = piece.rotation(progress: 1) * .pi / 180

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.keyTimes = [0, 0.78, 1]
        opacity.values = [1, 1, 0]

        let group = CAAnimationGroup()
        group.animations = [position, rotation, opacity]
        group.animations?.forEach { $0.duration = piece.duration }
        group.duration = piece.duration
        group.beginTime = beginTime
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.isRemovedOnCompletion = false
        // Keep delayed pieces hidden; the model opacity also leaves finished pieces invisible.
        group.fillMode = .forwards
        return group
    }
}
