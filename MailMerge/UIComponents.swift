import SwiftUI
import PDFKit

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImageName)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FileIconView: View {
    let systemImageName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.12))
            Image(systemName: systemImageName)
                .font(.title3)
                .foregroundStyle(color)
        }
        .frame(width: 40, height: 40)
    }
}

struct DropTargetView: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.separator)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlaceholderTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(.primary)
    }
}

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

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImageName)
                .font(.caption2)
            Text(status.label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(.secondary.opacity(0.12))
        )
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.05, progress))
                .stroke(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(progress * 100))")
                    .font(.title3.bold())
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .animation(.smooth(duration: 0.6), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress: \(Int(progress * 100)) percent complete")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

struct StepButton: View {
    let step: MergeStep
    let isSelected: Bool
    let isComplete: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isComplete ? .green : (isSelected ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .frame(width: 32, height: 32)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step.rawValue + 1)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
                Spacer()
                Image(systemName: step.systemImageName)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.clear)
                        .applyLiquidGlassIfAvailable()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.smooth(duration: 0.2), value: isSelected)
    }
}

struct StatCard: View {
    let systemImageName: String
    let value: String
    let label: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(label, systemImage: systemImageName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MappingProgressView: View {
    let mappedCount: Int
    let totalCount: Int

    var body: some View {
        let progress = totalCount == 0 ? 0 : Double(mappedCount) / Double(totalCount)
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress)
            Text("\(mappedCount) / \(totalCount) mapped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DataPreviewTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Row \(rowIndex + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            let value = rows[rowIndex].indices.contains(columnIndex)
                                ? rows[rowIndex][columnIndex]
                                : ""
                            GridRow {
                                Text(headers[columnIndex])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 140, alignment: .leading)
                                Text(value.isEmpty ? "—" : value)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

extension View {
    @ViewBuilder
    func applyLiquidGlassIfAvailable() -> some View {
        if #available(macOS 15.0, *) {
            self.glassEffect()
        } else {
            self
        }
    }

    @ViewBuilder
    func applyGlassButtonStyleIfAvailable(isProminent: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
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
