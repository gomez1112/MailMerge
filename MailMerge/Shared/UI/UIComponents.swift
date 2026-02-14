import SwiftUI
import PDFKit

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 32, height: 32)
                Text(title)
                    .font(.title2.bold())
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 42)
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
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - File Icon View

struct FileIconView: View {
    let systemImageName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
            Image(systemName: systemImageName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: 40, height: 40)
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
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(isHovering ? 0.14 : 0.08))
                    Image(systemName: systemImageName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 52, height: 52)
                VStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .foregroundStyle(isHovering ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Placeholder Tag

struct PlaceholderTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
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
        case .configured: return .blue
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(badgeColor.opacity(0.12))
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
                .stroke(Color.secondary.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 9, weight: .medium))
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
                    Circle()
                        .fill(stepIndicatorFill)
                        .frame(width: 28, height: 28)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step.rawValue + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                }
                Text(step.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .stepButtonBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .animation(.smooth(duration: 0.18), value: isSelected)
        .animation(.smooth(duration: 0.18), value: isComplete)
    }

    private var stepIndicatorFill: Color {
        if isComplete { return .green }
        if isSelected { return .accentColor }
        return Color.primary.opacity(0.1)
    }
}

private extension View {
    @ViewBuilder
    func stepButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            } else {
                self.background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImageName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(progress == 1 ? .green : .accentColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 5)
                    Capsule()
                        .fill(progress == 1 ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * progress, height: 5)
                }
            }
            .frame(height: 5)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            let value = rows[rowIndex].indices.contains(columnIndex)
                                ? rows[rowIndex][columnIndex]
                                : ""
                            GridRow {
                                Text(headers[columnIndex])
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 130, alignment: .leading)
                                Text(value.isEmpty ? "—" : value)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
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
            self.glassEffect()
        } else {
            self
        }
    }

    @ViewBuilder
    func applyGlassButtonStyleIfAvailable(isProminent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                self.buttonStyle(GlassProminentButtonStyle())
            } else {
                self.buttonStyle(GlassButtonStyle())
            }
        } else {
            self.buttonStyle(.bordered)
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
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
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }
}
