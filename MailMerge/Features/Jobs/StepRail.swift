import SwiftUI

/// The job's setup steps as a vertical rail. Each step shows its number until it's
/// complete, then a checkmark; connectors between steps fill in as they're completed,
/// and the selection highlight slides from step to step.
struct StepRail: View {
    let selection: MergeStep
    let isComplete: (MergeStep) -> Bool
    let isEnabled: (MergeStep) -> Bool
    let onSelect: (MergeStep) -> Void

    @Namespace private var selectionHighlight

    var body: some View {
        VStack(spacing: 0) {
            ForEach(MergeStep.allCases) { step in
                StepRailRow(
                    step: step,
                    isSelected: selection == step,
                    isComplete: isComplete(step),
                    isEnabled: isEnabled(step),
                    showsConnector: step != MergeStep.allCases.last,
                    highlightNamespace: selectionHighlight
                ) {
                    onSelect(step)
                }
            }
        }
    }
}

private struct StepRailRow: View {
    let step: MergeStep
    let isSelected: Bool
    let isComplete: Bool
    let isEnabled: Bool
    let showsConnector: Bool
    let highlightNamespace: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var indicatorSymbol: String {
        isComplete ? "checkmark.circle.fill" : "\(step.rawValue + 1).circle"
    }

    private var indicatorColor: Color {
        if isComplete { return .green }
        return isSelected ? .mergeformBlue : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Image(systemName: indicatorSymbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(indicatorColor)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(width: 28, height: 28)
                    if showsConnector {
                        Capsule()
                            .fill(isComplete ? Color.green.opacity(0.6) : Color.primary.opacity(0.1))
                            .frame(width: 2, height: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(step.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, showsConnector ? 0 : 8)
            .contentShape(.rect(cornerRadius: Metrics.tileRadius))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                        .fill(Color.mergeformBlue.opacity(0.11))
                        .matchedGeometryEffect(id: "selection", in: highlightNamespace)
                } else if isHovering && isEnabled {
                    RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .motion(Motion.lively, value: isComplete)
        .motion(Motion.quick, value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.rawValue + 1), \(step.title)")
        .accessibilityValue(isComplete ? "Complete" : "Not complete")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
