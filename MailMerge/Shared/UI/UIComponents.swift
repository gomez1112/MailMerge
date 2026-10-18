import AppKit
import PDFKit
import SwiftUI

// MARK: - Brand Colors

// The app's colors live in Assets.xcassets, and Xcode generates their `Color` symbols:
// - `mergeformBlue`: the blue from the app icon, for primary content and progress.
//   AccentColor uses the same values.
// - `mergeformOrange`: the orange from the app icon, for output, attention, and
//   in-progress states.
//   Both brand colors are slightly brighter in dark mode, and deeper with Increase
//   Contrast so text set in them stays readable.
// - `mergeformBackground`: page tint behind work surfaces.
// - `mergeformPanel`: card fill.
// - `mergeformStroke`: hairline border for cards and controls.
// - `mergeformSurface`: translucent raised fill, white in light mode and a faint tint
//   in dark mode. Apply `.opacity(_:)` to set its strength.

// MARK: - Section Header

/// The title of a setup step, with its icon, name, and a one-line explanation.
struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    var iconColor: Color = .mergeformBlue

    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.regular) {
            IconTile(systemImage: systemImageName, tint: iconColor, size: 52, isProminent: true)
                .symbolEffect(.bounce.up, value: hasAppeared)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title)
                    .bold()
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .onAppear { hasAppeared = true }
    }
}

// MARK: - Config Card

/// A card holding one group of a setup step's content.
struct ConfigCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

// MARK: - Card Label

/// The small uppercase title at the top of a card.
struct CardLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Metrics.tight) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.mergeformBlue)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - File Icon View

struct FileIconView: View {
    let systemImageName: String
    let color: Color

    var body: some View {
        IconTile(systemImage: systemImageName, tint: color, size: 44)
    }
}

// MARK: - Selected File Row

/// A chosen file or folder, with a button to choose a different one.
struct SelectedFileRow: View {
    let fileName: String
    let subtitle: String
    let systemImageName: String
    let color: Color
    let onChangeTap: () -> Void

    @State private var isConfirmed = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImageName, tint: color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.drawOn, isActive: !isConfirmed)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer(minLength: Metrics.regular)
            Button("Change…", action: onChangeTap)
                .controlSize(.small)
        }
        .padding(12)
        .background(color.opacity(0.06), in: .rect(cornerRadius: Metrics.tileRadius))
        .onAppear { isConfirmed = true }
    }
}

// MARK: - Drop Target View

/// A large target for dropping a file or folder, which also opens a file panel when
/// clicked. While the pointer is over it, the dashed border marches.
struct DropTargetView: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                IconTile(systemImage: systemImageName, size: 56, isProminent: isHovering)
                    .symbolEffect(.bounce, value: isHovering)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 168)
            .contentShape(.rect(cornerRadius: Metrics.cardRadius))
            .background {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Color.mergeformBlue.opacity(isHovering ? 0.08 : 0.03))
            }
            .overlay {
                TimelineView(.animation(paused: !isHovering || reduceMotion)) { context in
                    let phase = isHovering && !reduceMotion
                        ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 14
                        : 0
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(
                            isHovering ? Color.mergeformBlue : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6], dashPhase: -phase)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
    }
}

// MARK: - Placeholder Tag

struct PlaceholderTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(Color.mergeformBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.mergeformBlue.opacity(0.10), in: .capsule)
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

/// A job's status as a tinted capsule. The symbol morphs when the status changes.
struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImageName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: status == .running)
            Text(status.label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.14), in: .capsule)
        .foregroundStyle(status.tint)
        .motion(Motion.quick, value: status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

extension JobStatus {
    /// The color that represents the status.
    var tint: Color {
        switch self {
        case .draft: return .secondary
        case .configured: return .mergeformBlue
        case .running: return .mergeformOrange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Progress Ring

/// A circular progress indicator whose percentage rolls as it changes.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6
    var tint: Color = .mergeformBlue
    var showsPercentage = true

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.65), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsPercentage {
                Text(clampedProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: clampedProgress))
            }
        }
        .frame(width: size, height: size)
        .motion(Motion.standard, value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(clampedProgress, format: .percent.precision(.fractionLength(0))))
    }
}

// MARK: - Stat Card

/// A count with its icon and label. The number rolls when it changes.
struct StatCard: View {
    let systemImageName: String
    let value: String
    let label: String
    var iconColor: Color = .mergeformBlue

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImageName, tint: iconColor, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .cardSurface(padding: Metrics.regular)
        .motion(Motion.standard, value: value)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mapping Progress View

/// How many fields have a column, as a count and a bar that celebrates when every field
/// is mapped.
struct MappingProgressView: View {
    let mappedCount: Int
    let totalCount: Int

    private var progress: Double {
        totalCount == 0 ? 0 : Double(mappedCount) / Double(totalCount)
    }

    private var isComplete: Bool { totalCount > 0 && mappedCount == totalCount }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(mappedCount) of \(totalCount) fields mapped")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                if isComplete {
                    Label("All mapped", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: isComplete)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.mergeformBlue)
                        .contentTransition(.numericText(value: progress))
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: isComplete ? [.green.opacity(0.8), .green] : [Color.mergeformBlue.opacity(0.7), Color.mergeformBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: progress == 0 ? 0 : max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 8)
        }
        .motion(Motion.lively, value: mappedCount)
        .motion(Motion.lively, value: isComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mapping progress")
        .accessibilityValue("\(mappedCount) of \(totalCount) fields mapped")
    }
}

// MARK: - Data Preview Table

/// The first rows of a sheet as a compact table that scrolls sideways for wide sheets.
struct DataPreviewTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { column in
                        cell(headers[column].isEmpty ? "—" : headers[column])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }
                .background(Color.primary.opacity(0.04))
                Divider()
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(headers.indices, id: \.self) { column in
                            let value = rows[row].indices.contains(column) ? rows[row][column] : ""
                            cell(value.isEmpty ? "—" : value)
                                .font(.callout)
                                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                        }
                    }
                    .background(row.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                }
            }
        }
        .scrollIndicators(.automatic)
        .clipShape(.rect(cornerRadius: Metrics.tileRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .strokeBorder(Color.mergeformStroke)
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 110, maxWidth: 240, alignment: .leading)
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
        view.document = PDFDocument(data: data)
        context.coordinator.displayedData = data
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Replacing the document resets the scroll position and zoom, so only do it when
        // the PDF itself changed.
        guard context.coordinator.displayedData != data else { return }
        nsView.document = PDFDocument(data: data)
        context.coordinator.displayedData = data
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var displayedData: Data?
    }
}
