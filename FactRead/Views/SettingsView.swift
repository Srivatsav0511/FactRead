import SwiftData
import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Fact> { $0.isBookmarked }, sort: [SortDescriptor(\Fact.createdAt)]) private var bookmarkedFacts: [Fact]

    let onOpenFact: (Fact) -> Void
    var onDone: (() -> Void)? = nil

    @State private var lastHapticAt: Date = .distantPast
    @State private var narrator = FactNarrationManager.shared
    @State private var showNotificationsDisabledAlert = false

    private var resolvedThemeMode: ReaderThemeMode {
        colorScheme == .dark ? .dark : .light
    }

    private var palette: ReaderTheme.Palette {
        ReaderTheme.palette(for: resolvedThemeMode, typographyStyle: settings.readerTypographyStyle)
    }

    private var settingsScreenBackground: Color {
        if colorScheme == .dark {
            return Color(uiColor: .systemGroupedBackground)
        }
        return ReaderTheme.palette(for: .light, typographyStyle: .original).pageBackground
    }

    private var settingsRowBackground: Color {
        if colorScheme == .dark {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        return Color(hex: "FBF7EE")
    }

    private var bookmarkCount: Int {
        bookmarkedFacts.count
    }

    private var narrationLanguageCode: String {
        settings.appLanguage.bcp47Code
    }

    private var narrationVoices: [NarrationVoiceOption] {
        narrator.availableVoices(for: narrationLanguageCode)
    }

    private var selectedNarrationVoiceID: String {
        settings.narrationVoiceIdentifier(for: narrationLanguageCode) ?? "voice.auto"
    }

    var body: some View {
        NavigationStack {
            List {
                    Section {
                        NavigationLink {
                            CategoriesSettingsView(
                                selection: Binding(
                                    get: { settings.selectedCategories },
                                    set: { newValue in
                                        settings.applySelectedCategories(newValue)
                                        settingsChanged()
                                    }
                                ),
                                palette: palette,
                                screenBackground: settingsScreenBackground,
                                rowBackground: settingsRowBackground
                            )
                        } label: {
                            LabeledContent(text(.categoriesLabel)) {
                                Text("\(settings.selectedCategories.count)").foregroundStyle(.secondary)
                            }
                        }

                        NavigationLink {
                            BookmarksView(onOpenFact: { fact in
                                onOpenFact(fact)
                                onDone?()
                                dismiss()
                            }, palette: palette)
                        } label: {
                            LabeledContent(text(.bookmarksLabel)) {
                                Text("\(bookmarkCount)").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(text(.libraryHeader))
                    }

                    Section {
                        Toggle(text(.pageTextAnimationsLabel), isOn: Binding(
                            get: { settings.pageTextAnimationsEnabled },
                            set: { newValue in
                                settings.pageTextAnimationsEnabled = newValue
                                settingsChanged()
                            }
                        ))
                        .tint(.green)
                    } header: {
                        Text(text(.readingHeader))
                    } footer: {
                        Text(text(.readingFooter))
                    }

                    Section {
                        if narrationVoices.isEmpty {
                            Text(text(.voiceUnavailableFooter))
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(text(.voiceLabel), selection: Binding(
                                get: { selectedNarrationVoiceID },
                                set: { newValue in
                                    settings.setNarrationVoiceIdentifier(newValue, for: narrationLanguageCode)
                                    settingsChanged()
                                }
                            )) {
                                ForEach(narrationVoices) { voice in
                                    Text(voice.name).tag(voice.id)
                                }
                            }

                            Button(text(.voiceSampleButton)) {
                                narrator.playPreview(
                                    voiceIdentifier: selectedNarrationVoiceID,
                                    languageCode: narrationLanguageCode,
                                    sampleText: text(.voiceSampleText)
                                )
                            }
                        }
                    } header: {
                        Text(text(.voiceLabel))
                    } footer: {
                        Text(text(.voiceFooter))
                    }

                    Section {
                        Toggle(text(.remindersLabel), isOn: Binding(
                            get: { settings.alertsEnabled },
                            set: { enabled in
                                settings.alertsEnabled = enabled
                                settingsChanged()
                                Task { @MainActor in
                                    let success = await FactReminderNotifications.shared.sync(
                                        enabled: enabled,
                                        language: settings.appLanguage
                                    )
                                    if enabled && success == false {
                                        settings.alertsEnabled = false
                                        showNotificationsDisabledAlert = true
                                    }
                                }
                            }
                        ))
                        .tint(.green)
                    } header: {
                        Text(text(.alertsHeader))
                    } footer: {
                        Text(text(.alertsFooter))
                    }

                    Section {
                        LabeledContent(text(.versionLabel)) {
                            Text(appVersionString).foregroundStyle(.secondary)
                        }
                        if let websiteURL {
                            Link(destination: websiteURL) {
                                Label("Developer Website", systemImage: "globe")
                                    .symbolRenderingMode(.hierarchical)
                            }
                        } else {
                            LabeledContent("Developer Website") {
                                Text("Not set").foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            requestReview()
                        } label: {
                            Label {
                                Text(text(.rateUsLabel))
                            } icon: {
                                Image(systemName: "star")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.primary.opacity(0.75))
                            }
                        }
                    } header: {
                        Text(text(.aboutHeader))
                    }
                }
            .listRowBackground(settingsRowBackground)
            .listStyle(.insetGrouped)
            .tint(.accentColor)
            .scrollContentBackground(.hidden)
            .background(settingsScreenBackground)
            .navigationTitle(text(.settingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text(.doneButton)) { closeSettings() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .alert(text(.notificationsDisabledTitle), isPresented: $showNotificationsDisabledAlert) {
                Button(text(.openSettingsButton)) {
                    FactReminderNotifications.shared.openSystemSettings()
                }
                Button(text(.okButton), role: .cancel) {}
            } message: {
                Text(text(.notificationsDisabledMessage))
            }
        }
    }

    private func closeSettings() {
        onDone?()
        dismiss()
    }

    private func settingsChanged() {
        let now = Date()
        guard settings.hapticsEnabled else { return }
        guard now.timeIntervalSince(lastHapticAt) > 0.16 else { return }
        lastHapticAt = now
        HapticManager.shared.impact(.soft)
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return version
    }

    private var websiteURL: URL? {
        URL(string: DeveloperProfile.websiteURLString)
    }

    private func text(_ key: SettingsStringKey) -> String {
        SettingsStrings.english[key] ?? ""
    }
}

private enum DeveloperProfile {
    static let websiteURLString = "https://www.srivatsavkaramala.com"
}

private struct CategoriesSettingsView: View {
    @Binding var selection: Set<String>
    let palette: ReaderTheme.Palette
    let screenBackground: Color
    let rowBackground: Color
    @Environment(AppSettings.self) private var settings

    private var recommendations: [String] {
        settings.personalizedCategories(limit: 4, excluding: selection)
    }

    var body: some View {
        List {
                if recommendations.isEmpty == false {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(recommendations, id: \.self) { category in
                                    HStack(spacing: 8) {
                                        Image(systemName: symbol(for: category))
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(Fact.localizedCategory(category, language: settings.appLanguage.resolved))
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(CategoryStyle.accent(for: category, intensity: settings.categoryTintIntensity).opacity(0.45), lineWidth: 1)
                                    }
                                    .liquidGlassCard(cornerRadius: 14, isDark: palette.isDark)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        Button {
                            settings.applyPersonalizedCategoryMix(targetCount: 4)
                            selection = settings.selectedCategories
                            HapticManager.shared.notification(.success)
                        } label: {
                            Label("Apply Smart Mix", systemImage: "wand.and.stars")
                        }
                    } header: {
                        Text("Recommended For You")
                    } footer: {
                        Text("These suggestions adapt on-device based on your reading and bookmarks.")
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("\(selection.count) selected")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(rowBackground)

                    ForEach(Fact.allCategories, id: \.self) { category in
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(CategoryStyle.accent(for: category, intensity: settings.categoryTintIntensity).opacity(0.18))
                                Image(systemName: symbol(for: category))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CategoryStyle.accent(for: category, intensity: settings.categoryTintIntensity))
                            }
                            .frame(width: 26, height: 26)

                            Text(Fact.localizedCategory(category, language: settings.appLanguage.resolved))
                                .foregroundStyle(.primary)

                            Spacer()

                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { selection.contains(category) },
                                    set: { newValue in
                                        if newValue {
                                            selection.insert(category)
                                        } else if selection.count > 2 {
                                            selection.remove(category)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .tint(.green)
                            .disabled(selection.contains(category) && selection.count <= 2)
                        }
                    }
                } footer: {
                    Text(footerText)
                }
            }
        .listRowBackground(rowBackground)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(screenBackground)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleText: String {
        "Categories"
    }

    private var footerText: String {
        "Select at least two categories."
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

private struct ReadingGoalProgressCard: View {
    let progress: Double
    let secondsRead: Int
    let goalMinutes: Int
    let isGoalReached: Bool
    let isDark: Bool
    let reachedCaption: String
    let inProgressCaption: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(formattedReadTime)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(isDark ? 0.15 : 0.10))
                    .frame(height: 12)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.95), Color.white.opacity(0.65)]
                                : [Color.black.opacity(0.85), Color.black.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, animatedProgress * 220), height: 12)
                    .animation(.spring(response: 0.45, dampingFraction: 0.88), value: animatedProgress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(isGoalReached ? reachedCaption : subtitleText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isGoalReached)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: 14, isDark: isDark)
        .onAppear { animatedProgress = progress }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
    }

    private var formattedReadTime: String {
        let minutes = secondsRead / 60
        let remainingSeconds = secondsRead % 60
        let goal = goalMinutes
        return "\(minutes)m \(remainingSeconds)s / \(goal)m"
    }

    private var subtitleText: String {
        inProgressCaption
    }
}

private enum SettingsStringKey {
    case languageLabel, appearanceLabel, hapticsLabel, preferencesHeader
    case voiceLabel, voiceSystemDefaultLabel, voiceSampleButton, voiceFooter, voiceUnavailableFooter, voiceSampleText, voiceDownloadHint
    case readingGoalLabel, readingGoalAdjustLabel, readingGoalReachedCaption, readingGoalInProgressCaption
    case remindersLabel, alertsHeader, alertsFooter
    case resumeFromLastPageLabel, pageTurnStyleLabel, pageTurnSlide, pageTurnCurl
    case pageTextAnimationsLabel, typingSoundLabel, clearReadingPositionLabel, readingHeader, readingFooter
    case categoriesLabel, bookmarksLabel, libraryHeader, versionLabel, aboutHeader
    case rateUsLabel
    case settingsTitle, doneButton
    case notificationsDisabledTitle, openSettingsButton, okButton, notificationsDisabledMessage
    case lightTheme, darkTheme
}

private enum SettingsStrings {
    static let english: [SettingsStringKey: String] = [
        .languageLabel: "Language",
        .appearanceLabel: "Appearance",
        .hapticsLabel: "Haptics",
        .preferencesHeader: "Preferences",
        .voiceLabel: "Narration Voice",
        .voiceSystemDefaultLabel: "System Default",
        .voiceSampleButton: "Play Voice Sample",
        .voiceFooter: "Narration uses the voice configured in your iPhone settings for this language.",
        .voiceUnavailableFooter: "No voices are available for this language on this device.",
        .voiceSampleText: "This is a sample narration voice for FactRead.",
        .voiceDownloadHint: "To change voice, use iOS Settings > Accessibility > Spoken Content > Voices.",
        .readingGoalLabel: "Today's Reading Goal",
        .readingGoalAdjustLabel: "Adjust Goal Time",
        .readingGoalReachedCaption: "You hit your daily goal.",
        .readingGoalInProgressCaption: "Keep reading to hit today's goal.",
        .remindersLabel: "Reminders",
        .alertsHeader: "Alerts",
        .alertsFooter: "Daily reminders at 7:00 AM and 9:00 PM.",
        .resumeFromLastPageLabel: "Resume From Last Page",
        .pageTurnStyleLabel: "Page Turn Style",
        .pageTurnSlide: "Slide",
        .pageTurnCurl: "Curl",
        .pageTextAnimationsLabel: "Page Text Animations",
        .typingSoundLabel: "Typing Sound",
        .clearReadingPositionLabel: "Clear Reading Position",
        .readingHeader: "Reading",
        .readingFooter: "Animations also respect iOS Reduce Motion.",
        .categoriesLabel: "Categories",
        .bookmarksLabel: "Bookmarks",
        .libraryHeader: "Library",
        .versionLabel: "Version",
        .aboutHeader: "About",
        .rateUsLabel: "Rate Us",
        .settingsTitle: "Settings",
        .doneButton: "Done",
        .notificationsDisabledTitle: "Notifications Disabled",
        .openSettingsButton: "Open Settings",
        .okButton: "OK",
        .notificationsDisabledMessage: "Enable notifications in iOS Settings to receive reminders.",
        .lightTheme: "Light",
        .darkTheme: "Dark"
    ]
}
