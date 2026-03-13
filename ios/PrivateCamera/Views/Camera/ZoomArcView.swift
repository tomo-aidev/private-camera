import SwiftUI

/// Zoom control with compact threshold buttons and expandable horizontal slider.
/// - Default: compact lens buttons (0.5x, 1x, 2x) with exclusive active state
/// - Long-press: expands upward (~2.5x height) with horizontal slider
/// - X-axis drag: continuous zoom control with haptic at lens switch points
/// - Release: auto-collapse after delay
struct ZoomArcView: View {
    let thresholds: [(label: String, factor: CGFloat)]
    @Binding var currentZoom: CGFloat
    var displayDivisor: CGFloat = 1.0
    let onZoomSelected: (CGFloat) -> Void

    @State private var isExpanded = false
    @State private var isDragging = false

    private var minZoom: CGFloat { thresholds.first?.factor ?? 1.0 }
    private var maxZoom: CGFloat { max(thresholds.last?.factor ?? 2.0, 2.0) }
    private var zoomRange: CGFloat { maxZoom - minZoom }

    var body: some View {
        ZStack {
            if isExpanded {
                expandedSliderView
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            } else {
                compactButtonsView
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
    }

    // MARK: - Compact Buttons

    private var compactButtonsView: some View {
        HStack(spacing: 4) {
            ForEach(Array(thresholds.enumerated()), id: \.offset) { index, threshold in
                let isActive = activeThresholdIndex == index
                Button {
                    AppTheme.selectionFeedback()
                    onZoomSelected(threshold.factor)
                } label: {
                    Text(threshold.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? AppTheme.accentGreen : .white.opacity(0.6))
                        .frame(width: 44, height: 32)
                        .background(
                            Circle()
                                .fill(isActive
                                    ? AppTheme.accentGreen.opacity(0.15)
                                    : Color.white.opacity(0.08))
                                .frame(width: 36, height: 36)
                        )
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            AppTheme.mediumImpact()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = true
                            }
                        }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.black.opacity(0.3))
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(Capsule())
        )
    }

    // MARK: - Expanded Slider

    private var expandedSliderView: some View {
        VStack(spacing: 10) {
            // Current zoom value (display = raw / divisor)
            Text(String(format: "%.1fx", currentZoom / displayDivisor))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Horizontal slider
            GeometryReader { geo in
                let width = geo.size.width
                let thumbSize: CGFloat = 24
                let usable = max(1, width - thumbSize)
                let progress: CGFloat = zoomRange > 0
                    ? max(0, min(1, (currentZoom - minZoom) / zoomRange))
                    : 0.0
                let thumbX = thumbSize / 2 + usable * progress

                ZStack {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                        .padding(.horizontal, thumbSize / 2)

                    // Active fill
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(AppTheme.accentGreen.opacity(0.7))
                            .frame(width: max(4, thumbX), height: 4)
                        Spacer(minLength: 0)
                    }

                    // Threshold marks on track
                    ForEach(Array(thresholds.enumerated()), id: \.offset) { _, threshold in
                        let tp: CGFloat = zoomRange > 0
                            ? max(0, min(1, (threshold.factor - minZoom) / zoomRange))
                            : 0.0
                        let markX = thumbSize / 2 + usable * tp

                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .position(x: markX, y: geo.size.height / 2)
                    }

                    // Thumb
                    Circle()
                        .fill(AppTheme.accentGreen)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: AppTheme.accentGreen.opacity(0.4), radius: 6)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .position(x: thumbX, y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(1, (value.location.x - thumbSize / 2) / usable))
                            let newZoom = minZoom + zoomRange * fraction

                            // Haptic at threshold crossings
                            for threshold in thresholds {
                                let snapZone = zoomRange * 0.025
                                if abs(newZoom - threshold.factor) < snapZone
                                    && abs(currentZoom - threshold.factor) >= snapZone {
                                    AppTheme.selectionFeedback()
                                }
                            }

                            onZoomSelected(newZoom)
                        }
                        .onEnded { _ in
                            isDragging = false

                            // Snap to nearest threshold if close
                            let snapZone = zoomRange * 0.05
                            for threshold in thresholds {
                                if abs(currentZoom - threshold.factor) < snapZone {
                                    onZoomSelected(threshold.factor)
                                    break
                                }
                            }

                            // Collapse after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if !isDragging {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        isExpanded = false
                                    }
                                }
                            }
                        }
                )
            }
            .frame(height: 28)
            .padding(.horizontal, 8)

            // Threshold labels
            HStack {
                ForEach(Array(thresholds.enumerated()), id: \.offset) { index, threshold in
                    if index > 0 { Spacer() }
                    Text(threshold.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(activeThresholdIndex == index
                            ? AppTheme.accentGreen
                            : .white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.5))
                .background(
                    .ultraThinMaterial.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 20)
                )
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
        }
    }

    // MARK: - Helpers

    /// Returns the index of the single closest threshold (exclusive active state).
    /// Only ONE threshold is active at any time.
    private var activeThresholdIndex: Int? {
        guard !thresholds.isEmpty else { return nil }
        var bestIndex = 0
        var bestDist: CGFloat = .infinity
        for (i, t) in thresholds.enumerated() {
            let d = abs(t.factor - currentZoom)
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        return bestIndex
    }
}
