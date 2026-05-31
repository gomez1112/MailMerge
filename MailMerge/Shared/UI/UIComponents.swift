import SwiftUI
import PDFKit
import AppKit

// MARK: - Brand Colors

extension Color {
    /// Primary action blue used for focused controls and active workflow states.
    static let mergeformBlue = Color(red: 0.10, green: 0.38, blue: 0.78)
    /// Warm accent used for attention, automation, and in-progress states.
    static let mergeformOrange = Color(red: 0.93, green: 0.48, blue: 0.18)
    /// Deep ink used in branded surfaces and document previews.
    static let mergeformInk = Color(red: 0.07, green: 0.09, blue: 0.13)
    /// Soft page tint used for work surfaces.
    static let mergeformBackground = Color(red: 0.95, green: 0.96, blue: 0.94)
    /// Elevated panel fill with a warmer paper tone.
    static let mergeformPanel = Color(red: 0.99, green: 0.985, blue: 0.965)
    /// Subtle dividing stroke for cards and controls.
    static let mergeformStroke = Color.black.opacity(0.08)
}

extension Text {
    @ViewBuilder
    func bold(_ isActive: Bool) -> some View {
        if isActive {
            bold()
        } else {
            self
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    var iconColor: Color = .mergeformBlue

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImageName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.72), in: .rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.mergeformStroke)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Color.mergeformInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Config Card

/// A styled container replacing GroupBox for config step content.
struct ConfigCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.mergeformPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.mergeformStroke)
            )
    }
}

// MARK: - File Icon View

struct FileIconView: View {
    let systemImageName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.12))
            Image(systemName: systemImageName)
                .font(.title3)
                .foregroundStyle(color)
        }
        .frame(width: 42, height: 42)
    }
}

// MARK: - Drop Target View

struct DropTargetView: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImageName)
                    .font(.title2)
                    .foregroundStyle(Color.mergeformBlue)
                    .frame(width: 48, height: 48)
                    .background(Color.mergeformBlue.opacity(isHovering ? 0.16 : 0.10), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.doc")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Color.mergeformBlue.opacity(0.06) : Color.white.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.4, dash: [7, 5])
                    )
                    .foregroundStyle(isHovering ? Color.mergeformBlue.opacity(0.6) : Color.mergeformStroke)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.2), value: isHovering)
    }
}

// MARK: - Placeholder Tag

struct PlaceholderTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.mergeformBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.mergeformBlue.opacity(0.10))
            )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: JobStatus

    private var badgeColor: Color {
        switch status {
        case .draft: return .secondary
        case .configured: return .mergeformBlue
        case .running: return .mergeformOrange
        case .completed: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2)
                .bold()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(badgeColor.opacity(0.13))
        )
        .foregroundStyle(badgeColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.mergeformBlue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(progress * 100))")
                    .font(.headline)
                    .bold()
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 68, height: 68)
        .animation(.smooth(duration: 0.5), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(Int(progress * 100)) percent complete")
    }
}

// MARK: - Step Button

struct StepButton: View {
    let step: MergeStep
    let isSelected: Bool
    let isComplete: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(stepIndicatorFill)
                        .frame(width: 30, height: 30)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step.rawValue + 1)")
                            .font(.callout)
                            .bold()
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                }
                Text(step.title)
                    .font(.callout)
                    .bold(isSelected)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                Spacer()
                if isSelected {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .stepButtonBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .animation(.smooth(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.2), value: isComplete)
    }

    private var stepIndicatorFill: Color {
        if isComplete { return .green }
        if isSelected { return .mergeformBlue }
        return Color.primary.opacity(0.10)
    }
}

private extension View {
    @ViewBuilder
    func stepButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            } else {
                self.background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.mergeformBlue.opacity(0.10))
                )
            }
        } else {
            self
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let systemImageName: String
    let value: String
    let label: String
    var iconColor: Color = .mergeformBlue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImageName)
                .font(.body)
                .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconColor.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(iconColor.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Mapping Progress View

struct MappingProgressView: View {
    let mappedCount: Int
    let totalCount: Int

    private var progress: Double {
        totalCount == 0 ? 0 : Double(mappedCount) / Double(totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(mappedCount) of \(totalCount) mapped")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.callout)
                    .bold()
                    .foregroundStyle(progress == 1 ? .green : .mergeformBlue)
            }
            ProgressView(value: progress)
                .tint(progress == 1 ? .green : .mergeformBlue)
            .animation(.smooth(duration: 0.4), value: progress)
        }
    }
}

// MARK: - Data Preview Table

struct DataPreviewTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Row \(rowIndex + 1)")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            let value = rows[rowIndex].indices.contains(columnIndex)
                                ? rows[rowIndex][columnIndex]
                                : ""
                            GridRow {
                                Text(headers[columnIndex])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 130, alignment: .leading)
                                Text(value.isEmpty ? "—" : value)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(14)
                .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PDF Preview View

struct PDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(data: data)
    }
}

// MARK: - Liquid Glass Extensions

extension View {
    @ViewBuilder
    func applyLiquidGlassIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            self
        }
    }

}

// MARK: - Inline Label Row

/// A reusable horizontal label+content row for form-like layouts.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.callout)
                .bold()
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Card Section Label

struct CardLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mergeformBlue)
            }
            Text(title)
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
}
