import SwiftUI

public enum DuplicateActionChoice: String, CaseIterable, Identifiable {
    case moveToTrash
    case deletePermanently
    case selectInExplorer

    public var id: String { rawValue }

    @MainActor
    public func localizedTitle(using loc: LocalizationManager = .shared) -> String {
        switch self {
        case .moveToTrash:
            return loc.text(es: "Mover marcados a la Papelera", en: "Move checked to Trash")
        case .deletePermanently:
            return loc.text(es: "Eliminar marcados permanentemente", en: "Delete checked permanently")
        case .selectInExplorer:
            return loc.text(es: "Seleccionar marcados en el explorador", en: "Select checked in explorer")
        }
    }
}

public struct DuplicateFinderModalView: View {
    @Bindable var viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    @ViewState private var groups: [DuplicateGroup] = []
    @ViewState private var checkedURLs: Set<URL> = []
    @ViewState private var includeSubfolders: Bool = false
    @ViewState private var isScanning: Bool = true
    @ViewState private var selectedAction: DuplicateActionChoice = .moveToTrash

    private var loc: LocalizationManager { LocalizationManager.shared }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(loc.text(
                    es: "Buscar archivos duplicados en «\(viewModel.currentFolderTitle)»",
                    en: "Find Duplicate Files in «\(viewModel.currentFolderTitle)»"
                ))
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer()

                Toggle(loc.text(es: "Incluir subcarpetas", en: "Include subfolders"), isOn: $includeSubfolders)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .onChange(of: includeSubfolders) { _, _ in
                        Task { await runScan() }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            if isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(loc.text(es: "Analizando archivos por tamaño y SHA-256…", en: "Scanning files by size and SHA-256…"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text(loc.text(es: "No se encontraron archivos duplicados.", en: "No duplicate files found."))
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    let totalWasted = groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
                    Text(loc.text(
                        es: "\(groups.count) grupo(s) • Espacio recuperable: \(Self.byteFormatter.string(fromByteCount: totalWasted))",
                        en: "\(groups.count) group(s) • Reclaimable space: \(Self.byteFormatter.string(fromByteCount: totalWasted))"
                    ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(loc.text(es: "Pre-marcar duplicados", en: "Check Duplicates")) {
                        premarkDuplicates(keepOldest: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(loc.text(es: "Desmarcar todos", en: "Uncheck All")) {
                        checkedURLs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))

                Divider()

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.text(
                                    es: "\(group.items.count) copias idénticas • \(Self.byteFormatter.string(fromByteCount: group.fileSize)) c/u",
                                    en: "\(group.items.count) identical copies • \(Self.byteFormatter.string(fromByteCount: group.fileSize)) each"
                                ))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                    let isChecked = checkedURLs.contains(item.url)
                                    HStack(spacing: 8) {
                                        Toggle(isOn: Binding(
                                            get: { checkedURLs.contains(item.url) },
                                            set: { newValue in
                                                if newValue {
                                                    checkedURLs.insert(item.url)
                                                } else {
                                                    checkedURLs.remove(item.url)
                                                }
                                            }
                                        )) {
                                            EmptyView()
                                        }
                                        .toggleStyle(.checkbox)

                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(item.name)
                                                    .font(.system(size: 12.5, weight: .medium))
                                                    .lineLimit(1)
                                                if idx == 0 {
                                                    Text(loc.text(es: "Original", en: "Original"))
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(.green)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(Color.green.opacity(0.14)))
                                                } else if isChecked {
                                                    Text(loc.text(es: "Duplicado", en: "Duplicate"))
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(.orange)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                                                }
                                            }
                                            Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.head)
                                        }

                                        Spacer()

                                        Text(item.formattedModificationDate)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isChecked ? Color.orange.opacity(0.08) : Color.clear)
                                    )
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                    .padding(14)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Picker(loc.text(es: "Acción:", en: "Action:"), selection: $selectedAction) {
                    ForEach(DuplicateActionChoice.allCases) { choice in
                        Text(choice.localizedTitle(using: loc)).tag(choice)
                    }
                }
                .frame(maxWidth: 280)

                Spacer()

                Button(loc.text(es: "Cerrar", en: "Close")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(loc.text(
                    es: "Aplicar (\(checkedURLs.count))",
                    en: "Apply (\(checkedURLs.count))"
                )) {
                    applySelectedAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(checkedURLs.isEmpty || isScanning)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 660, height: 500)
        .task {
            await runScan()
        }
    }

    private func runScan() async {
        isScanning = true
        let found = await DuplicateFinderService.findDuplicates(
            in: viewModel.currentDirectoryURL,
            includeSubfolders: includeSubfolders,
            includeHidden: viewModel.showHiddenFiles
        )
        groups = found
        premarkDuplicates(keepOldest: true)
        isScanning = false
    }

    private func premarkDuplicates(keepOldest: Bool) {
        var toCheck: Set<URL> = []
        for group in groups {
            let items = keepOldest ? group.items : group.items.reversed()
            for (idx, item) in items.enumerated() where idx > 0 {
                toCheck.insert(item.url)
            }
        }
        checkedURLs = toCheck
    }

    private func applySelectedAction() {
        let targets = Array(checkedURLs)
        guard !targets.isEmpty else { return }

        switch selectedAction {
        case .moveToTrash:
            dismiss()
            viewModel.moveURLsToTrashFromExternal(targets)
        case .deletePermanently:
            dismiss()
            viewModel.deleteURLsPermanentlyFromExternal(targets)
        case .selectInExplorer:
            viewModel.selectedItemIDs = Set(targets.map(\.standardizedFileURL))
            viewModel.selectionAnchorID = targets.first?.standardizedFileURL
            dismiss()
        }
    }
}
