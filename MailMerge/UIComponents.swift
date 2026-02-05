import SwiftUI
import PDFKit

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let systemImageName: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImageName)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FileIconView: View {
    let systemImageName: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.opacity(0.15))
            .overlay(
                Image(systemName: systemImageName)
                    .font(.title2)
                    .foregroundStyle(color)
            )
            .frame(width: 44, height: 44)
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
                    .font(.title)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.secondary.opacity(0.5))
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
        HStack(spacing: 6) {
            Image(systemName: status.systemImageName)
            Text(status.label)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.15))
        )
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.05, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption)
        }
        .frame(width: 60, height: 60)
        .animation(.snappy, value: progress)
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step.rawValue + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                    Text(step.systemImageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .hidden()
                }
                Spacer()
                Image(systemName: step.systemImageName)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct StatCard: View {
    let systemImageName: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImageName)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
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
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.caption.bold())
                            .frame(minWidth: 120, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                    }
                }
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            let value = rows[rowIndex].indices.contains(columnIndex)
                                ? rows[rowIndex][columnIndex]
                                : ""
                            Text(value)
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(8)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
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
