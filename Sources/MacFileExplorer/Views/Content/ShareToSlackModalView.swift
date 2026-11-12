import SwiftUI
import AppKit

private enum SlackDestinationFilter: String, CaseIterable, Identifiable {
    case all
    case channels
    case people

    var id: String { rawValue }

    @MainActor
    func title(using loc: LocalizationManager) -> String {
        switch self {
        case .all:
            return loc.text(es: "Todos", en: "All")
        case .channels:
            return loc.text(es: "# Canales", en: "# Channels")
        case .people:
            return loc.text(es: "@ Personas", en: "@ People")
        }
    }
}

/// Diálogo modal nativo para "Compartir con Slack" desde el menú contextual.
/// Permite buscar y autocompletar canales (#) o personas (@), gestionar el directorio,
/// escribir un mensaje opcional y activar/desactivar la opción en los menús contextuales.
public struct ShareToSlackModalView: View {
    let viewModel: ExplorerViewModel
    @Environment(\.dismiss) private var dismiss

    @Bindable private var slackPrefs = SlackPreferences.shared
    @ViewState private var destination: String = ""
    @ViewState private var message: String = ""
    @ViewState private var selectedFilter: SlackDestinationFilter = .all
    @ViewState private var isAddingCustom: Bool = false
    @ViewState private var newDestinationText: String = ""
    @ViewState private var newDestinationIsPerson: Bool = false

    private var loc: LocalizationManager { LocalizationManager.shared }

    public init(viewModel: ExplorerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    filesPreviewSection

                    destinationSearchAndSelectionSection

                    messageSection

                    helperTipSection
                }
                .padding(20)
            }

            Divider()

            footerBar
        }
        .frame(width: 520, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if destination.isEmpty, let first = slackPrefs.recentDestinations.first {
                destination = first
            }
        }
    }

    // MARK: - Barra Superior

    private var headerBar: some View {
        HStack(spacing: 10) {
            if let slackIcon = viewModel.slackMenuIcon() {
                Image(nsImage: slackIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
            }

            Text(loc.text(es: "Compartir con Slack", en: "Share with Slack"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Sección de Previsualización de Archivos

    private var filesPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.text(
                es: "Archivos a compartir (\(viewModel.slackShareURLs.count))",
                en: "Files to share (\(viewModel.slackShareURLs.count))"
            ))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(viewModel.slackShareURLs.prefix(3), id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 20, height: 20)

                        Text(url.lastPathComponent)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(fileSizeString(for: url))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }

                if viewModel.slackShareURLs.count > 3 {
                    Text(loc.text(
                        es: "... y \(viewModel.slackShareURLs.count - 3) archivo(s) más",
                        en: "... and \(viewModel.slackShareURLs.count - 3) more file(s)"
                    ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                }
            }
        }
    }

    // MARK: - Sección de Destino (Búsqueda, Autocompletado y Directorio)

    private var destinationSearchAndSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc.text(es: "Canal o persona de Slack", en: "Slack channel or person"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    isAddingCustom.toggle()
                    if isAddingCustom {
                        newDestinationText = ""
                        newDestinationIsPerson = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAddingCustom ? "chevron.up" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(loc.text(es: "Nuevo contacto/canal", en: "New contact/channel"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // Barra de búsqueda / escritura interactiva
            HStack(spacing: 8) {
                Image(systemName: destinationIconName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                TextField(
                    loc.text(
                        es: "Buscar o escribir canal (#) o persona (@)...",
                        en: "Search or enter channel (#) or person (@)..."
                    ),
                    text: $destination
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    submitShare()
                }

                if !destination.isEmpty {
                    Button {
                        destination = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Borrar búsqueda", en: "Clear search"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )

            // Panel para agregar nuevo elemento si se abrió
            if isAddingCustom {
                addCustomDestinationCard
            }

            // Pestañas de filtrado (Todos | # Canales | @ Personas)
            HStack(spacing: 6) {
                ForEach(SlackDestinationFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Text(filter.title(using: loc))
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            Text("(\(countForFilter(filter)))")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if slackPrefs.savedDestinations != PersistenceService.defaultSlackDirectory {
                    Button {
                        slackPrefs.resetDirectoryToDefaults()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.text(es: "Restablecer sugerencias predeterminadas", en: "Reset default suggestions"))
                }
            }
            .padding(.top, 2)

            // Lista de autocompletado y sugerencias
            autocompleteDirectoryList

            // Chips horizontales de accesos recientes
            if !slackPrefs.recentDestinations.isEmpty {
                recentDestinationsChips
            }
        }
    }

    // MARK: - Tarjeta para Añadir Nuevo Contacto / Canal

    private var addCustomDestinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $newDestinationIsPerson) {
                    Text(loc.text(es: "# Canal", en: "# Channel")).tag(false)
                    Text(loc.text(es: "@ Persona", en: "@ Person")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                TextField(
                    newDestinationIsPerson
                        ? loc.text(es: "nombre o usuario", en: "name or username")
                        : loc.text(es: "nombre-del-canal", en: "channel-name"),
                    text: $newDestinationText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    saveCustomDestination()
                }

                Button {
                    saveCustomDestination()
                } label: {
                    Text(loc.text(es: "Guardar", en: "Save"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDestinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func saveCustomDestination() {
        let raw = newDestinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let formatted: String
        if newDestinationIsPerson {
            formatted = raw.hasPrefix("@") ? raw : "@\(raw)"
        } else {
            formatted = raw.hasPrefix("#") ? raw : "#\(raw)"
        }
        slackPrefs.addDestination(formatted)
        destination = formatted
        newDestinationText = ""
        isAddingCustom = false
    }

    // MARK: - Lista de Autocompletado

    private var autocompleteDirectoryList: some View {
        VStack(spacing: 0) {
            let matches = filteredDestinations
            let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 2) {
                    if matches.isEmpty && !canCreateFromQuery {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            Text(loc.text(
                                es: "No se encontraron coincidencias para \"\(destination)\"",
                                en: "No matches found for \"\(destination)\""
                            ))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        // Coincidencias existentes
                        ForEach(matches, id: \.self) { item in
                            destinationRow(item: item)
                        }

                        // Opción de crear a partir de lo que escribió el usuario si no existe exacto
                        if canCreateFromQuery {
                            createFromQueryRows(query: trimmed)
                        }
                    }
                }
                .padding(4)
            }
            .frame(height: 140)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func destinationRow(item: String) -> some View {
        let isSelected = destination.caseInsensitiveCompare(item) == .orderedSame
        let isPerson = isPersonDestination(item)

        return HStack(spacing: 8) {
            Image(systemName: isPerson ? "person.crop.circle.fill" : "number")
                .font(.system(size: 12))
                .foregroundStyle(isPerson ? Color.purple : Color.accentColor)
                .frame(width: 16)

            Text(item)
                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)

            Spacer()

            Text(isPerson ? loc.text(es: "Persona", en: "Person") : loc.text(es: "Canal", en: "Channel"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    slackPrefs.removeDestination(item)
                    if destination.caseInsensitiveCompare(item) == .orderedSame {
                        destination = ""
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.text(es: "Eliminar de sugerencias", en: "Remove from suggestions"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            destination = item
        }
    }

    private var canCreateFromQuery: Bool {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !slackPrefs.savedDestinations.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    @ViewBuilder
    private func createFromQueryRows(query: String) -> some View {
        Divider().padding(.vertical, 2)

        if query.hasPrefix("@") {
            Button {
                slackPrefs.addDestination(query)
                destination = query
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text(loc.text(
                        es: "Añadir persona «\(query)» a sugerencias",
                        en: "Add person «\(query)» to suggestions"
                    ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        } else if query.hasPrefix("#") {
            Button {
                slackPrefs.addDestination(query)
                destination = query
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text(loc.text(
                        es: "Añadir canal «\(query)» a sugerencias",
                        en: "Add channel «\(query)» to suggestions"
                    ))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                Button {
                    let channel = "#\(query)"
                    slackPrefs.addDestination(channel)
                    destination = channel
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "number")
                            .font(.system(size: 10.5))
                        Text(loc.text(es: "+ Añadir #\(query)", en: "+ Add #\(query)"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    let person = "@\(query)"
                    slackPrefs.addDestination(person)
                    destination = person
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10.5))
                        Text(loc.text(es: "+ Añadir @\(query)", en: "+ Add @\(query)"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
    }

    // MARK: - Chips de Destinos Recientes

    private var recentDestinationsChips: some View {
        HStack(spacing: 6) {
            Text(loc.text(es: "Recientes:", en: "Recent:"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(slackPrefs.recentDestinations, id: \.self) { chip in
                        Button {
                            destination = chip
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isPersonDestination(chip) ? "person.fill" : "number")
                                    .font(.system(size: 9))
                                Text(chip)
                                    .font(.system(size: 11, weight: destination == chip ? .semibold : .regular))
                            }
                            .foregroundStyle(destination == chip ? Color.white : Color.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(destination == chip ? Color.accentColor : Color.secondary.opacity(0.12))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Sección de Mensaje

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.text(es: "Mensaje adicional (opcional)", en: "Additional message (optional)"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            TextField(
                loc.text(
                    es: "Escribe un comentario o nota para acompañar el archivo...",
                    en: "Write a comment or note to accompany the file..."
                ),
                text: $message,
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.system(size: 12.5))
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Nota informativa

    private var helperTipSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)

            Text(loc.text(
                es: "Al pulsar «Compartir», se abrirá Slack, se seleccionará la conversación y se adjuntarán los archivos seleccionados automáticamente.",
                en: "Clicking «Share» will open Slack, jump to the chosen conversation, and automatically attach the selected files."
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(6)
    }

    // MARK: - Barra Inferior

    private var footerBar: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $slackPrefs.isShareToSlackEnabled) {
                Text(loc.text(
                    es: "Mostrar «Añadir a Slack» en menús contextuales",
                    en: "Show «Add to Slack» in context menus"
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(loc.text(es: "Cancelar", en: "Cancel"))
                    .frame(minWidth: 70)
            }
            .keyboardShortcut(.cancelAction)

            Button {
                submitShare()
            } label: {
                HStack(spacing: 6) {
                    if let slackIcon = viewModel.slackMenuIcon() {
                        Image(nsImage: slackIcon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(loc.text(es: "Compartir en Slack", en: "Share in Slack"))
                }
                .fontWeight(.semibold)
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.slackShareURLs.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Lógica de Envío y Ayudantes

    private func submitShare() {
        guard !viewModel.slackShareURLs.isEmpty else { return }
        let urlsToShare = viewModel.slackShareURLs
        let dest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = message
        if !dest.isEmpty {
            slackPrefs.addDestination(dest)
        }
        dismiss()
        viewModel.sendToSlack(urls: urlsToShare, destination: dest, message: msg)
    }

    private var destinationIconName: String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "@") {
            return "person.crop.circle.fill"
        } else if trimmed.starts(with: "#") {
            return "number"
        } else {
            return "magnifyingglass"
        }
    }

    private func countForFilter(_ filter: SlackDestinationFilter) -> Int {
        switch filter {
        case .all:
            return slackPrefs.savedDestinations.count
        case .channels:
            return slackPrefs.savedDestinations.filter { !isPersonDestination($0) }.count
        case .people:
            return slackPrefs.savedDestinations.filter { isPersonDestination($0) }.count
        }
    }

    private var filteredDestinations: [String] {
        let all = slackPrefs.savedDestinations
        let byFilter: [String]
        switch selectedFilter {
        case .all:
            byFilter = all
        case .channels:
            byFilter = all.filter { !isPersonDestination($0) }
        case .people:
            byFilter = all.filter { isPersonDestination($0) }
        }

        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return byFilter }

        let queryStripped = query.trimmingCharacters(in: CharacterSet(charactersIn: "#@"))
        return byFilter.filter { item in
            let lower = item.lowercased()
            if lower.contains(query) { return true }
            if !queryStripped.isEmpty && lower.contains(queryStripped) { return true }
            return false
        }
    }

    private func isPersonDestination(_ dest: String) -> Bool {
        dest.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
    }

    private func fileSizeString(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
