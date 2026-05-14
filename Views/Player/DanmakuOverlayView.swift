//
//  DanmakuOverlayView.swift
//  KazumiTV
//
//  Danmaku (Bullet Comments) Overlay using SwiftUI Canvas
//

import SwiftUI
import UIKit

struct DanmakuOverlayView: View {
    let danmakus: [DanmakuItem]
    let currentTime: TimeInterval
    let isPlaying: Bool
    let isEnabled: Bool
    let playbackRate: Float
    let fontSize: CGFloat
    let opacity: Double
    let showTop: Bool
    let showScroll: Bool
    let showBottom: Bool
    let duration: TimeInterval
    let area: Double
    let massiveMode: Bool

    @State private var timeAnchor: DanmakuTimeAnchor?

    private var lineHeight: CGFloat {
        max(fontSize + 10, fontSize * 1.35)
    }

    private var maxVisibleDanmakus: Int {
        massiveMode ? 120 : 50
    }

    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let renderTime = renderedCurrentTime(at: timeline.date)

            Canvas { context, size in
                guard isEnabled, size.width > 0, size.height > 0 else { return }

                let visibleDanmakus = getVisibleDanmakus(at: renderTime)
                let scrollLaneCandidates = getScrollLaneCandidates(at: renderTime)
                let scrollLanes = calculateScrollLanes(size: size, laneCandidates: scrollLaneCandidates)
                let topLanes = calculateFixedLanes(height: size.height, visibleDanmakus: visibleDanmakus.filter { $0.type == .top })
                let bottomLanes = calculateFixedLanes(height: size.height, visibleDanmakus: visibleDanmakus.filter { $0.type == .bottom })

                for danmaku in visibleDanmakus {
                    let textSize = textSize(for: danmaku)

                    var position: CGPoint
                    var anchor: UnitPoint

                    switch danmaku.type {
                    case .scroll:
                        guard let y = scrollLanes[danmaku.id] else { continue }
                        let x = scrollXPosition(for: danmaku, textWidth: textSize.width, screenWidth: size.width, at: renderTime)
                        position = CGPoint(x: x, y: y)
                        anchor = .leading

                    case .top:
                        guard let y = topLanes[danmaku.id] else { continue }
                        position = CGPoint(x: size.width / 2, y: y)
                        anchor = .center

                    case .bottom:
                        guard let y = bottomLanes[danmaku.id] else { continue }
                        position = CGPoint(x: size.width / 2, y: size.height - y)
                        anchor = .center
                    }

                    drawDanmaku(danmaku, at: position, anchor: anchor, in: &context)
                }
            }
        }
        .onAppear {
            resetTimeAnchor(to: currentTime)
        }
        .onChange(of: currentTime) { _, newValue in
            resetTimeAnchor(to: newValue)
        }
        .onChange(of: isPlaying) { _, _ in
            resetTimeAnchor(to: currentTime)
        }
        .onChange(of: playbackRate) { _, _ in
            resetTimeAnchor(to: currentTime)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Render Clock

    private func renderedCurrentTime(at date: Date) -> TimeInterval {
        guard isEnabled,
              isPlaying,
              playbackRate > 0,
              let timeAnchor else {
            return currentTime
        }

        let elapsed = date.timeIntervalSince(timeAnchor.date)
        return max(0, timeAnchor.mediaTime + elapsed * Double(playbackRate))
    }

    private func resetTimeAnchor(to mediaTime: TimeInterval) {
        timeAnchor = DanmakuTimeAnchor(mediaTime: mediaTime, date: Date())
    }

    // MARK: - Visible Danmakus

    private func getVisibleDanmakus(at renderTime: TimeInterval) -> [DanmakuItem] {
        danmakus.filter { danmaku in
            let elapsed = renderTime - danmaku.time
            let visible = elapsed >= 0 && elapsed <= displayDuration(for: danmaku)

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
        .sorted { $0.time < $1.time }
        .prefix(maxVisibleDanmakus)
        .map { $0 }
    }

    private func getScrollLaneCandidates(at renderTime: TimeInterval) -> [DanmakuItem] {
        let lookbackDuration = max(2.0, duration > 0 ? duration : 8.0) * 2

        return danmakus
            .filter { danmaku in
                danmaku.type == .scroll &&
                danmaku.time <= renderTime &&
                renderTime - danmaku.time <= lookbackDuration
            }
            .sorted { $0.time < $1.time }
    }

    // MARK: - Lane Calculation

    private func calculateScrollLanes(size: CGSize, laneCandidates: [DanmakuItem]) -> [UUID: CGFloat] {
        let laneCount = max(1, Int(danmakuHeight(for: size.height) / lineHeight))
        var laneStates = Array<ScrollLaneState?>(repeating: nil, count: laneCount)
        var result: [UUID: CGFloat] = [:]

        for danmaku in laneCandidates {
            let textWidth = textSize(for: danmaku).width
            let spacing: CGFloat = 28

            let preferredLane = laneStates.firstIndex { state in
                canPlaceScrollDanmaku(
                    danmaku,
                    textWidth: textWidth,
                    after: state,
                    screenWidth: size.width,
                    spacing: spacing
                )
            }
            let selectedLane: Int?

            if let preferredLane {
                selectedLane = preferredLane
            } else if massiveMode {
                selectedLane = laneStates.enumerated().min { lhs, rhs in
                    scrollLaneRightEdge(lhs.element, at: danmaku.time, screenWidth: size.width) <
                    scrollLaneRightEdge(rhs.element, at: danmaku.time, screenWidth: size.width)
                }?.offset
            } else {
                selectedLane = nil
            }

            guard let selectedLane else { continue }
            result[danmaku.id] = CGFloat(selectedLane) * lineHeight + lineHeight / 2
            laneStates[selectedLane] = ScrollLaneState(danmaku: danmaku, textWidth: textWidth)
        }

        return result
    }

    private func calculateFixedLanes(height: CGFloat, visibleDanmakus: [DanmakuItem]) -> [UUID: CGFloat] {
        let laneCount = max(1, Int(danmakuHeight(for: height) / lineHeight))
        var result: [UUID: CGFloat] = [:]

        for (index, danmaku) in visibleDanmakus.sorted(by: { $0.time < $1.time }).enumerated() {
            guard index < laneCount else { break }
            let y = CGFloat(index) * lineHeight + lineHeight / 2
            result[danmaku.id] = y
        }

        return result
    }

    private func danmakuHeight(for height: CGFloat) -> CGFloat {
        let clampedArea = min(max(area, 0.1), 1.0)
        return max(lineHeight, height * CGFloat(clampedArea))
    }

    private func scrollXPosition(for danmaku: DanmakuItem, textWidth: CGFloat, screenWidth: CGFloat, at renderTime: TimeInterval) -> CGFloat {
        let elapsed = renderTime - danmaku.time
        let progress = CGFloat(elapsed / displayDuration(for: danmaku))
        return screenWidth - progress * (screenWidth + textWidth)
    }

    private func canPlaceScrollDanmaku(
        _ danmaku: DanmakuItem,
        textWidth: CGFloat,
        after previousState: ScrollLaneState?,
        screenWidth: CGFloat,
        spacing: CGFloat
    ) -> Bool {
        guard let previousState else { return true }

        let previous = previousState.danmaku
        let previousDuration = displayDuration(for: previous)
        let previousEndTime = previous.time + previousDuration
        guard previousEndTime > danmaku.time else { return true }

        let previousRightEdgeAtStart = scrollLaneRightEdge(
            previousState,
            at: danmaku.time,
            screenWidth: screenWidth
        )
        guard previousRightEdgeAtStart + spacing < screenWidth else {
            return false
        }

        let previousSpeed = (screenWidth + previousState.textWidth) / CGFloat(previousDuration)
        let currentSpeed = (screenWidth + textWidth) / CGFloat(displayDuration(for: danmaku))
        guard currentSpeed > previousSpeed else { return true }

        let currentLeftAtPreviousEnd = screenWidth - CGFloat(previousEndTime - danmaku.time) * currentSpeed
        return currentLeftAtPreviousEnd > spacing
    }

    private func scrollLaneRightEdge(_ state: ScrollLaneState?, at renderTime: TimeInterval, screenWidth: CGFloat) -> CGFloat {
        guard let state else { return -CGFloat.greatestFiniteMagnitude }
        let x = scrollXPosition(
            for: state.danmaku,
            textWidth: state.textWidth,
            screenWidth: screenWidth,
            at: renderTime
        )
        return x + state.textWidth
    }

    private func displayDuration(for danmaku: DanmakuItem) -> TimeInterval {
        max(2.0, duration > 0 ? duration : danmaku.duration)
    }

    private func textSize(for danmaku: DanmakuItem) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)
        ]
        return (danmaku.text as NSString).size(withAttributes: attributes)
    }

    private func drawDanmaku(_ danmaku: DanmakuItem, at position: CGPoint, anchor: UnitPoint, in context: inout GraphicsContext) {
        let shadowText = Text(danmaku.text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.black.opacity(min(opacity, 0.88)))
        let fillText = Text(danmaku.text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(danmaku.color.opacity(opacity))

        let offsets: [CGPoint] = [
            CGPoint(x: -1.4, y: 0),
            CGPoint(x: 1.4, y: 0),
            CGPoint(x: 0, y: -1.4),
            CGPoint(x: 0, y: 1.4),
            CGPoint(x: -1.0, y: -1.0),
            CGPoint(x: 1.0, y: 1.0)
        ]

        for offset in offsets {
            context.draw(
                shadowText,
                at: CGPoint(x: position.x + offset.x, y: position.y + offset.y),
                anchor: anchor
            )
        }

        context.draw(fillText, at: position, anchor: anchor)
    }
}

private struct DanmakuTimeAnchor {
    let mediaTime: TimeInterval
    let date: Date
}

private struct ScrollLaneState {
    let danmaku: DanmakuItem
    let textWidth: CGFloat
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
            isPlaying: true,
            isEnabled: true,
            playbackRate: 1.0,
            fontSize: 18,
            opacity: 1.0,
            showTop: true,
            showScroll: true,
            showBottom: true,
            duration: 8.0,
            area: 1.0,
            massiveMode: false
        )
    }
}
