import SwiftUI
import UIKit

struct ProjectDrawerView: View {
    enum Section: CaseIterable, Identifiable {
        case files
        case search
        case packages

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .files: "Files"
            case .search: "Search"
            case .packages: "Packages"
            }
        }

        var systemImage: String {
            switch self {
            case .files: "folder"
            case .search: "magnifyingglass"
            case .packages: "square.grid.2x2"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .files: "projectFilesTab"
            case .search: "projectSearchTab"
            case .packages: "projectPackagesTab"
            }
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedSection: Section = .files
    @State private var campaignExpanded = true
    @State private var charactersExpanded = true

    @Binding var searchText: String
    @Binding var searchFocused: Bool
    let presentationSettled: Bool
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let close: () -> Void
    let openPackages: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProjectDrawerHeader(close: close)

            Picker("Project section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.subheadline)
                        .accessibilityLabel(section.title)
                        .accessibilityIdentifier(section.accessibilityIdentifier)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .padding(.horizontal, 4)
            .onChange(of: selectedSection) { _, section in
                if section == .packages {
                    openPackages()
                }
            }

            if selectedSection == .files {
                ProjectActionRow()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider().overlay(PlayerTheme.panelStroke)

            switch selectedSection {
            case .files:
                ProjectFileTree(
                    campaignExpanded: $campaignExpanded,
                    charactersExpanded: $charactersExpanded
                )
            case .search:
                ProjectSearch(
                    searchText: $searchText,
                    searchFocused: $searchFocused
                )
            case .packages:
                Color.clear
            }

            Divider().overlay(PlayerTheme.panelStroke)
            ProjectDrawerFooter()
                .offset(y: searchFocused ? safeAreaBottom : 0)
        }
        .padding(.top, safeAreaTop)
        .padding(.bottom, safeAreaBottom)
        .foregroundStyle(PlayerTheme.primaryText)
        .background {
            DrawerMaterialBackground(isOpaque: reduceTransparency)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .accessibilityIdentifier("projectDrawer")
        .accessibilityValue(presentationSettled ? "Settled" : "Transitioning")
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private enum ProjectLayout {
    case folders
    case files
}

private struct ProjectActionRow: View {
    @State private var selectedLayout: ProjectLayout = .folders

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ProjectActionButton(
                    systemName: "doc.badge.plus",
                    label: "New file",
                    identifier: "projectNewFile"
                )
                ProjectActionButton(
                    systemName: "folder.badge.plus",
                    label: "New folder",
                    identifier: "projectNewFolder"
                )
                ProjectActionButton(
                    systemName: "square.and.arrow.down",
                    label: "Import files",
                    identifier: "projectImportFiles"
                )
                ProjectActionButton(
                    systemName: "arrow.clockwise",
                    label: "Refresh files",
                    identifier: "projectRefreshFiles"
                )
                ProjectLayoutSelector(selectedLayout: $selectedLayout)
            }

            HStack(spacing: 4) {
                ProjectActionButton(
                    systemName: "doc.badge.plus",
                    label: "New file",
                    identifier: "projectNewFile"
                )
                ProjectActionButton(
                    systemName: "folder.badge.plus",
                    label: "New folder",
                    identifier: "projectNewFolder"
                )
                Menu {
                    Button("Import files", systemImage: "square.and.arrow.down") {}
                        .disabled(true)
                    Button("Refresh files", systemImage: "arrow.clockwise") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More project actions")
                .accessibilityIdentifier("projectActionOverflow")

                ProjectLayoutSelector(selectedLayout: $selectedLayout)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projectActionRow")
    }
}

private struct ProjectLayoutSelector: View {
    @Binding var selectedLayout: ProjectLayout

    var body: some View {
        HStack(spacing: 0) {
            ProjectLayoutButton(
                systemName: "folder.fill",
                label: "Folder view",
                identifier: "projectFolderView",
                selected: selectedLayout == .folders
            ) {
                selectedLayout = .folders
            }
            ProjectLayoutButton(
                systemName: "doc.text",
                label: "File view",
                identifier: "projectFileView",
                selected: selectedLayout == .files
            ) {
                selectedLayout = .files
            }
        }
        .frame(height: 44)
        .background(Color.white.opacity(0.06), in: Capsule())
    }
}

private struct ProjectLayoutButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(selected ? Color.white.opacity(0.10) : .clear, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ProjectActionButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let identifier: String

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.68)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct ProjectDrawerHeader: View {
    let close: () -> Void

    var body: some View {
        HStack {
            Button(action: close) {
                Label("Exit Game", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit Game")
            .accessibilityIdentifier("closeProjectDrawer")
            Spacer(minLength: 8)
        }
        .padding(.top, 0)
        .padding(.horizontal, 12)
    }
}

private struct ProjectFileTree: View {
    @Binding var campaignExpanded: Bool
    @Binding var charactersExpanded: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(isExpanded: $campaignExpanded) {
                    VStack(spacing: 4) {
                        FileTreeRow(icon: "map", color: .cyan, title: "World Map", count: nil)
                        FileTreeRow(icon: "book.closed", color: .orange, title: "Lore", count: 12)
                        FileTreeRow(icon: "signpost.right", color: .green, title: "Current Scene", count: 4)
                    }
                    .padding(.leading, 12)
                } label: {
                    FileTreeRow(icon: "folder.fill", color: PlayerTheme.accent, title: "Campaign", count: 18)
                }

                DisclosureGroup(isExpanded: $charactersExpanded) {
                    VStack(spacing: 4) {
                        FileTreeRow(icon: "person.crop.square", color: .purple, title: "Mara Vey", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .indigo, title: "The Lantern Rider", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .orange, title: "Archivist Ren", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .mint, title: "Glass Warden", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .green, title: "Mossbound Scout", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .cyan, title: "River Oracle", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .red, title: "Ash Cartographer", count: nil)
                        FileTreeRow(icon: "person.crop.square", color: .blue, title: "Night Courier", count: nil)
                    }
                    .padding(.leading, 12)
                } label: {
                    FileTreeRow(icon: "person.2.fill", color: .purple, title: "Characters", count: 8)
                }

                FileTreeRow(icon: "sparkles", color: .pink, title: "Unresolved Threads", count: 3)
                FileTreeRow(icon: "dice.fill", color: .red, title: "Rules", count: 5)
            }
            .padding(16)
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier("projectFileTree")
    }
}

private struct FileTreeRow: View {
    let icon: String
    let color: Color
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            Text(title)
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlayerTheme.secondaryText)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title), \($0) items" } ?? title)
    }
}

private struct ProjectSearch: View {
    @Binding var searchText: String
    @Binding var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PlayerTheme.secondaryText)
                ProjectSearchTextField(
                    text: $searchText,
                    isFocused: $searchFocused
                )
                .frame(minHeight: 44)
                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.035))

            Divider().overlay(PlayerTheme.panelStroke)

            Text(searchText.isEmpty ? "Search names, places, files, and lore." : "No fixture results match your search.")
                .font(.subheadline)
                .foregroundStyle(PlayerTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .accessibilityIdentifier("projectSearchEmptyState")

            Spacer()
        }
    }
}

@MainActor
private struct ProjectSearchTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = "Search project"
        textField.returnKeyType = .search
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.textColor = .label
        textField.tintColor = UIColor(PlayerTheme.accent)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.accessibilityIdentifier = "projectSearchField"
        textField.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        context.coordinator.textField = textField
        textField.inputAccessoryView = context.coordinator.makeInputAccessory()
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        if textField.text != text {
            textField.text = text
        }
        if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: max(44, uiView.intrinsicContentSize.height)
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ProjectSearchTextField
        weak var textField: UITextField?

        init(parent: ProjectSearchTextField) {
            self.parent = parent
        }

        func makeInputAccessory() -> UIView {
            let accessory = SearchKeyboardAccessoryView(
                frame: CGRect(x: 0, y: 0, width: 0, height: 48)
            )
            accessory.autoresizingMask = [.flexibleWidth]
            accessory.onDismiss = { [weak self] in
                self?.dismissKeyboard()
            }
            return accessory
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            updateFocus(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            updateFocus(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            dismissKeyboard()
            return true
        }

        @objc private func dismissKeyboard() {
            guard let textField else { return }
            parent.isFocused = false
            textField.resignFirstResponder()
            DispatchQueue.main.async {
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: textField
                )
            }
        }

        private func updateFocus(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.isFocused = focused
            }
        }
    }

    static func dismantleUIView(
        _ textField: UITextField,
        coordinator: Coordinator
    ) {
        if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
        textField.inputAccessoryView = nil
        textField.delegate = nil
        coordinator.textField = nil
    }
}

@MainActor
final class SearchKeyboardAccessoryView: UIView {
    let chromeView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    let previousButton = UIButton(type: .custom)
    let nextButton = UIButton(type: .custom)
    let dismissButton = UIButton(type: .custom)
    var onDismiss: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        configureButtons()
        configureChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    private func configureButtons() {
        configure(
            previousButton,
            systemName: "chevron.up",
            label: "Previous search field"
        )
        previousButton.isEnabled = false

        configure(
            nextButton,
            systemName: "chevron.down",
            label: "Next search field"
        )
        nextButton.isEnabled = false

        configure(
            dismissButton,
            systemName: "checkmark",
            label: "Dismiss keyboard"
        )
        dismissButton.accessibilityIdentifier = "dismissSearchKeyboard"
        dismissButton.tintColor = .label
        dismissButton.addTarget(
            self,
            action: #selector(didTapDismiss),
            for: .touchUpInside
        )
    }

    private func configure(
        _ button: UIButton,
        systemName: String,
        label: String
    ) {
        let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .semibold
        )
        button.setImage(
            UIImage(
                systemName: systemName,
                withConfiguration: symbolConfiguration
            ),
            for: .normal
        )
        button.accessibilityLabel = label
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureChrome() {
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.clipsToBounds = true
        chromeView.layer.cornerRadius = 24
        chromeView.layer.cornerCurve = .continuous
        chromeView.layer.borderWidth = 0.5
        chromeView.layer.borderColor = UIColor.white
            .withAlphaComponent(0.08)
            .cgColor
        chromeView.contentView.backgroundColor = UIColor.white
            .withAlphaComponent(0.035)
        addSubview(chromeView)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let controls = UIStackView(arrangedSubviews: [
            previousButton,
            nextButton,
            spacer,
            dismissButton
        ])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.distribution = .fill
        controls.spacing = 0
        controls.translatesAutoresizingMaskIntoConstraints = false
        chromeView.contentView.addSubview(controls)

        NSLayoutConstraint.activate([
            chromeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            chromeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            chromeView.topAnchor.constraint(equalTo: topAnchor),
            chromeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: chromeView.contentView.leadingAnchor, constant: 4),
            controls.trailingAnchor.constraint(equalTo: chromeView.contentView.trailingAnchor, constant: -4),
            controls.topAnchor.constraint(equalTo: chromeView.contentView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: chromeView.contentView.bottomAnchor)
        ])
    }

    @objc private func didTapDismiss() {
        onDismiss?()
    }
}

struct PackageSheetView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case project = "Project Packages"
        case community = "Community Packages"

        var id: Self { self }

        var accessibilityIdentifier: String {
            switch self {
            case .project: "packageProjectTab"
            case .community: "packageCommunityTab"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: Section = .community
    @State private var searchText = ""
    @State private var newestFirst = true
    @State private var installedPackageIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Packages", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close packages")
                .accessibilityIdentifier("closePackageSheet")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)

            Divider().overlay(PlayerTheme.panelStroke)

            HStack(spacing: 0) {
                ForEach(Section.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Text(section.rawValue.uppercased())
                            .font(.subheadline.weight(.heavy))
                            .tracking(0.9)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(
                                        section == selectedSection
                                            ? PlayerTheme.primaryText
                                            : Color.white.opacity(0.08)
                                    )
                                    .frame(height: section == selectedSection ? 2 : 0.5)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(section.accessibilityIdentifier)
                    .accessibilityAddTraits(section == selectedSection ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(PlayerTheme.secondaryText)
                            TextField("Search packages", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .submitLabel(.search)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))

                        Button {
                            newestFirst.toggle()
                        } label: {
                            Label(
                                newestFirst ? "Updated" : "Popular",
                                systemImage: "arrow.up.arrow.down"
                            )
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("packageSort")
                    }

                    PackageFixtureCard(
                        packageID: featuredPackageID,
                        title: selectedSection == .community
                            ? "Lantern Road Compendium"
                            : "Roadside Encounters",
                        detail: selectedSection == .community
                            ? "A reusable local package of characters, lore, and encounter notes."
                            : "Four local scenes and six character references for the current project.",
                        colors: [.indigo.opacity(0.76), .purple.opacity(0.42), .black.opacity(0.72)],
                        identifier: "packageFixtureCard",
                        installIdentifier: "packageInstall",
                        installed: installedPackageIDs.contains(featuredPackageID),
                        toggleInstallation: {
                            toggleInstallation(for: featuredPackageID)
                        }
                    )
                    PackageFixtureCard(
                        packageID: "community-high-pass-weather",
                        title: "High Pass Weather",
                        detail: "Atmosphere notes and scene prompts for a changing mountain route.",
                        colors: [.teal.opacity(0.60), .blue.opacity(0.42), .black.opacity(0.74)],
                        identifier: "packageSecondaryCard",
                        installIdentifier: "packageSecondaryInstall",
                        installed: installedPackageIDs.contains("community-high-pass-weather"),
                        toggleInstallation: {
                            toggleInstallation(for: "community-high-pass-weather")
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(PlayerTheme.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("packageSheet")
    }

    private var featuredPackageID: String {
        selectedSection == .community
            ? "community-lantern-road"
            : "project-roadside-encounters"
    }

    private func toggleInstallation(for packageID: String) {
        if installedPackageIDs.contains(packageID) {
            installedPackageIDs.remove(packageID)
        } else {
            installedPackageIDs.insert(packageID)
        }
    }
}

private struct PackageFixtureCard: View {
    let packageID: String
    let title: String
    let detail: String
    let colors: [Color]
    let identifier: String
    let installIdentifier: String
    let installed: Bool
    let toggleInstallation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Label("Local creator", systemImage: "person.crop.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(Color.black.opacity(0.62), in: Capsule())
                    .padding(10)
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(PlayerTheme.secondaryText)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    Label("12 files", systemImage: "doc")
                    Label("3 types", systemImage: "square.stack.3d.up")
                    Label("8m", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(PlayerTheme.secondaryText)

                HStack {
                    Label(installed ? "Installed locally" : "0 installs", systemImage: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundStyle(PlayerTheme.secondaryText)
                    Spacer()
                    Button(action: toggleInstallation) {
                        Label(installed ? "Installed" : "Install", systemImage: installed ? "checkmark" : "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(PlayerTheme.primaryText, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(installed ? "Installed" : "Install")
                    .accessibilityIdentifier(installIdentifier)
                }
            }
            .padding(14)
        }
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .id(packageID)
    }
}

private struct ProjectDrawerFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            ProjectUtilityRow(title: "Settings", systemImage: "gearshape")
            ProjectUtilityRow(title: "Trash", systemImage: "trash")

            HStack(spacing: 10) {
                Circle()
                    .fill(PlayerTheme.accent.gradient)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text("RC")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.72))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Player").font(.subheadline.weight(.semibold))
                    Text("On this device").font(.caption).foregroundStyle(PlayerTheme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("projectProfileCard")
        }
        .padding(8)
    }
}

private struct ProjectUtilityRow: View {
    @State private var noticePresented = false

    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Button {
            noticePresented = true
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .alert(title, isPresented: $noticePresented) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("This control is unavailable in the local fixture.")
        }
    }
}

struct DrawerMaterialBackground: View {
    let isOpaque: Bool

    var body: some View {
        ZStack {
            if isOpaque {
                Color(red: 0.035, green: 0.038, blue: 0.045)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                Color(red: 0.035, green: 0.038, blue: 0.045).opacity(0.92)
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 0.5)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }
}

private struct ProjectDrawerPreview: View {
    @State private var searchFocused = false

    var body: some View {
        ProjectDrawerView(
            searchText: .constant(""),
            searchFocused: $searchFocused,
            presentationSettled: true,
            safeAreaTop: 0,
            safeAreaBottom: 0,
            close: {},
            openPackages: {}
        )
        .frame(width: 310)
        .preferredColorScheme(.dark)
    }
}

#Preview("Project Drawer") {
    ProjectDrawerPreview()
}
