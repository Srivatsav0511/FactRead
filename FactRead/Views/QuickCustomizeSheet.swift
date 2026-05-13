import SwiftUI

struct QuickCustomizeSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var panelStroke: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }

    private var dividerTone: Color {
        Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.62 : 0.42)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCard
                topicsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text("Pick Categories")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .padding(.horizontal, 14)
                }
                .liquidGlassButtonStyle(fallbackShape: Capsule(style: .continuous))
            }

            Text("Choose what you read. FactRead will prioritize these topics across your selected categories.")
                .font(.system(size: 17, weight: .regular, design: .default))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("\(settings.selectedCategories.count) selected")
                    .font(.system(size: 19, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(panelStroke, lineWidth: 1))
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Topics")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(Fact.allCategories.enumerated()), id: \.element) { index, category in
                    QuickCategoryToggleRow(
                        category: category,
                        symbolName: symbol(for: category),
                        isOn: Binding(
                            get: { settings.selectedCategories.contains(category) },
                            set: { enabled in
                                if enabled {
                                    settings.selectedCategories.insert(category)
                                } else if settings.selectedCategories.count > 2 {
                                    settings.selectedCategories.remove(category)
                                }
                            }
                        ),
                        canTurnOff: !(settings.selectedCategories.contains(category) && settings.selectedCategories.count <= 2)
                    )

                    if index < Fact.allCategories.count - 1 {
                        Divider()
                            .overlay(dividerTone)
                            .padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidGlassCard(cornerRadius: 22)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(panelStroke, lineWidth: 1))
        }
    }

    private func symbol(for category: String) -> String {
        switch category {
        case "Science": return "flask"
        case "Space": return "sparkles"
        case "Nature": return "leaf"
        case "Human Body": return "figure"
        case "History": return "building.columns"
        case "Technology": return "cpu"
        case "Psychology": return "brain"
        case "Ocean": return "water.waves"
        case "Animals": return "pawprint"
        case "Movies": return "film"
        default: return "circle.grid.2x2"
        }
    }
}

private struct QuickCategoryToggleRow: View {
    let category: String
    let symbolName: String
    @Binding var isOn: Bool
    let canTurnOff: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(width: 34)

            Text(Fact.localizedCategory(category, language: .english))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
                .disabled(!canTurnOff && isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}
