import SwiftUI
import UIKit

enum Palette {
    static let paper = Color(red: 0.957, green: 0.937, blue: 0.894)
    static let card = Color(red: 1.0, green: 0.992, blue: 0.973)
    static let ink = Color(red: 0.122, green: 0.137, blue: 0.125)
    static let muted = Color(red: 0.427, green: 0.443, blue: 0.424)
    static let line = Color(red: 0.902, green: 0.863, blue: 0.796)
    static let duck = Color(red: 0.953, green: 0.706, blue: 0.173)
    static let duckDark = Color(red: 0.769, green: 0.537, blue: 0.031)
    static let beak = Color(red: 0.937, green: 0.545, blue: 0.141)
    static let teal = Color(red: 0.071, green: 0.537, blue: 0.490)
    static let tealSoft = Color(red: 0.890, green: 0.953, blue: 0.937)
    static let red = Color(red: 0.851, green: 0.259, blue: 0.259)
    static let warn = Color(red: 0.541, green: 0.392, blue: 0.0)
    static let warnSoft = Color(red: 1.0, green: 0.957, blue: 0.839)
}

struct DuckShape: View {
    var size: CGFloat = 128

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 128
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            var body = Path()
            body.addEllipse(in: CGRect(x: 28 * s, y: 58 * s, width: 72 * s, height: 56 * s))
            context.fill(body, with: .color(Palette.duck))

            var head = Path()
            head.addEllipse(in: CGRect(x: 46 * s, y: 26 * s, width: 52 * s, height: 52 * s))
            context.fill(head, with: .color(Palette.duck))

            var eye = Path()
            eye.addEllipse(in: CGRect(x: 75 * s, y: 41 * s, width: 10 * s, height: 10 * s))
            context.fill(eye, with: .color(Palette.ink))

            var beak = Path()
            beak.move(to: p(96, 54))
            beak.addCurve(to: p(112, 66), control1: p(106, 56), control2: p(112, 62))
            beak.addCurve(to: p(94, 70), control1: p(112, 70), control2: p(104, 70))
            beak.closeSubpath()
            context.fill(beak, with: .color(Palette.beak))

            var footL = Path()
            footL.addEllipse(in: CGRect(x: 44 * s, y: 104 * s, width: 20 * s, height: 8 * s))
            var footR = Path()
            footR.addEllipse(in: CGRect(x: 68 * s, y: 104 * s, width: 20 * s, height: 8 * s))
            context.fill(footL, with: .color(Palette.beak))
            context.fill(footR, with: .color(Palette.beak))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(red: 0.26, green: 0.20, blue: 0.09).opacity(0.08), radius: 14, y: 8)
    }
}

struct Chip: View {
    var text: String
    var kind: Kind = .plain

    enum Kind { case plain, ok, warn }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    private var foreground: Color {
        switch kind {
        case .plain: Palette.ink
        case .ok: Palette.teal
        case .warn: Palette.warn
        }
    }

    private var background: Color {
        switch kind {
        case .plain: .white
        case .ok: Palette.tealSoft
        case .warn: Palette.warnSoft
        }
    }
}

struct CameraFeed: View {
    @State private var image: UIImage?
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(red: 0.82, green: 0.76, blue: 0.62)
            }
        }
        .accessibilityIdentifier("camera-feed")
        .onReceive(timer) { _ in
            Task.detached {
                guard let url = URL(string: DuckRpc.cameraStill),
                      let data = try? Data(contentsOf: url),
                      let img = UIImage(data: data)
                else { return }
                await MainActor.run { image = img }
            }
        }
    }
}

struct DriveStick: View {
    @EnvironmentObject private var model: AppModel
    @State private var knob = CGSize.zero
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let travel: CGFloat = 48
    private let maxLinear = 0.3
    private let maxAngular = 1.5

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.992, blue: 0.973),
                            Color(red: 0.953, green: 0.933, blue: 0.894),
                            Color(red: 0.910, green: 0.875, blue: 0.816),
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 90
                    )
                )
                .frame(width: 176, height: 176)
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            Circle()
                .fill(Palette.duck)
                .frame(width: 64, height: 64)
                .offset(knob)
                .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("stick-drive")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let x = max(-1, min(1, value.translation.width / travel))
                    let y = max(-1, min(1, value.translation.height / travel))
                    knob = CGSize(width: x * travel, height: y * travel)
                    model.notifyMove(vx: Double(-y) * maxLinear, vyaw: Double(-x) * maxAngular)
                }
                .onEnded { _ in
                    knob = .zero
                    model.haltDrive()
                }
        )
        .onReceive(timer) { _ in
            if knob != .zero {
                let x = Double(knob.width / travel)
                let y = Double(knob.height / travel)
                model.notifyMove(vx: -y * maxLinear, vyaw: -x * maxAngular)
            }
        }
    }
}
