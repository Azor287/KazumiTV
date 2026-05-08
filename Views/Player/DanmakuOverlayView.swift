//
//  DanmakuOverlayView.swift
//  KazumiTV
//
//  Danmaku (Bullet Comments) Overlay using SwiftUI Canvas
//

import SwiftUI

struct DanmakuOverlayView: View {
    let danmakus: [DanmakuItem]
    let currentTime: TimeInterval
    let isEnabled: Bool
    let fontSize: CGFloat
    let opacity: Double
    let showTop: Bool
    let showScroll: Bool
    let showBottom: Bool

    @State private var activeDanmakus: [ActiveDanmaku] = []

    private let lineHeight: CGFloat = 30
    private let maxVisibleCount = 50

    var body: some View {
        Canvas { context, size in
            guard isEnabled else { return }

            let visibleDanmakus = getVisibleDanmakus()
            let topLanes = calculateTopLanes(width: size.width, visibleDanmakus: visibleDanmakus.filter { $0.type == .top })
            let bottomLanes = calculateBottomLanes(width: size.width, visibleDanmakus: visibleDanmakus.filter { $0.type == .bottom })

            for danmaku in visibleDanmakus {
                let text = Text(danmaku.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(danmaku.color.opacity(opacity))

                // Measure text using NSAttributedString on tvOS
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)
                ]
                let textSize = (danmaku.text as NSString).size(withAttributes: attributes)

                var position: CGPoint

                switch danmaku.type {
                case .scroll:
                    let elapsed = currentTime - danmaku.time
                    let danmakuWidth = textSize.width + 20
                    let x = size.width - (elapsed * danmakuWidth / danmaku.duration)
                    let y = danmaku.yPosition * size.height
                    position = CGPoint(x: x, y: y)

                case .top:
                    if let lane = topLanes[danmaku.id] {
                        position = CGPoint(x: size.width / 2, y: lane.minY)
                    } else {
                        continue
                    }

                case .bottom:
                    if let lane = bottomLanes[danmaku.id] {
                        position = CGPoint(x: size.width / 2, y: size.height - lane.minY)
                    } else {
                        continue
                    }
                }

                // Draw background for better visibility
                let bgRect = CGRect(
                    x: position.x - 4,
                    y: position.y - fontSize / 2 - 2,
                    width: textSize.width + 8,
                    height: fontSize + 4
                )
                context.fill(
                    Path(roundedRect: bgRect, cornerRadius: 4),
                    with: .color(.black.opacity(0.3))
                )

                context.draw(text, at: position, anchor: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Visible Danmakus

    private func getVisibleDanmakus() -> [DanmakuItem] {
        return danmakus.filter { danmaku in
            let elapsed = currentTime - danmaku.time
            let visible = elapsed >= 0 && elapsed <= danmaku.duration + 1

            guard visible else { return false }

            switch danmaku.type {
            case .scroll:
                return showScroll
            case .top:
                return showTop
            case .bottom:
                return showBottom
            }
        }
        .prefix(maxVisibleCount)
        .map { $0 }
    }

    // MARK: - Lane Calculation

    private func calculateTopLanes(width: CGFloat, visibleDanmakus: [DanmakuItem]) -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        var occupiedLanes: [(y: CGFloat, endX: CGFloat)] = []

        for danmaku in visibleDanmakus.sorted(by: { $0.time < $1.time }) {
            let laneHeight = fontSize + 8
            let y = CGFloat(occupiedLanes.count) * lineHeight + lineHeight

            if y > 100 {
                break
            }

            let lane = CGRect(x: 0, y: y, width: width, height: laneHeight)
            result[danmaku.id] = lane
            occupiedLanes.append((y: y, endX: width))
        }

        return result
    }

    private func calculateBottomLanes(width: CGFloat, visibleDanmakus: [DanmakuItem]) -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        var occupiedLanes: [(y: CGFloat, endX: CGFloat)] = []

        for danmaku in visibleDanmakus.sorted(by: { $0.time < $1.time }) {
            let laneHeight = fontSize + 8
            let y = CGFloat(occupiedLanes.count) * lineHeight + lineHeight

            if y > 100 {
                break
            }

            let lane = CGRect(x: 0, y: y, width: width, height: laneHeight)
            result[danmaku.id] = lane
            occupiedLanes.append((y: y, endX: width))
        }

        return result
    }
}

// MARK: - Active Danmaku (for animation tracking)

struct ActiveDanmaku: Identifiable {
    let id: UUID
    let text: String
    let time: TimeInterval
    let type: DanmakuType
    let color: Color
    let yPosition: CGFloat
    let duration: TimeInterval
    var xOffset: CGFloat = 0
}

// MARK: - Danmaku Controls View

struct DanmakuControlsView: View {
    @Binding var isEnabled: Bool
    @Binding var fontSize: CGFloat
    @Binding var opacity: Double
    @Binding var showTop: Bool
    @Binding var showScroll: Bool
    @Binding var showBottom: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("弹幕设置")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { isEnabled.toggle() }) {
                    Image(systemName: isEnabled ? "captions.bubble.fill" : "captions.bubble")
                        .font(.title2)
                        .foregroundColor(isEnabled ? .yellow : .gray)
                }
                .buttonStyle(.plain)
            }

            if isEnabled {
                DanmakuToggleButton(title: "顶部弹幕", isOn: $showTop)
                DanmakuToggleButton(title: "滚动弹幕", isOn: $showScroll)
                DanmakuToggleButton(title: "底部弹幕", isOn: $showBottom)

                HStack {
                    Text("透明度")
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1f", opacity))
                        .foregroundColor(.yellow)
                        .frame(width: 40)
                }

                HStack {
                    Button(action: { opacity = max(0.3, opacity - 0.1) }) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)

                    Button(action: { opacity = min(1.0, opacity + 0.1) }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("字体大小")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(fontSize))")
                        .foregroundColor(.yellow)
                        .frame(width: 40)
                }

                HStack {
                    Button(action: { fontSize = max(12, fontSize - 2) }) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)

                    Button(action: { fontSize = min(32, fontSize + 2) }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Custom Toggle Button for tvOS

struct DanmakuToggleButton: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(isOn ? .yellow : .gray)
                Text(title)
                    .foregroundColor(.white)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        DanmakuOverlayView(
            danmakus: DanmakuItem.samples,
            currentTime: 2.0,
            isEnabled: true,
            fontSize: 18,
            opacity: 1.0,
            showTop: true,
            showScroll: true,
            showBottom: true
        )
    }
}
