import SwiftUI

struct RelayView: View {
    private enum Field: Hashable { case listenPort, remoteHost, remotePort }
    private enum StorageKey: String { case listenPort, remoteHost, remotePort, selectedProto }

    @State private var engine = RelayEngine()
    @AppStorage(StorageKey.listenPort.rawValue) private var listenPort = ""
    @AppStorage(StorageKey.remoteHost.rawValue) private var remoteHost = ""
    @AppStorage(StorageKey.remotePort.rawValue) private var remotePort = ""
    @AppStorage(StorageKey.selectedProto.rawValue) private var selectedProto: RelayProtocol = .udp
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private var pendingConfig: RelayConfig? {
        try? RelayConfig(
            listenPort: listenPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            proto: selectedProto
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                listenSection
                remoteSection
                protocolSection
                controlSection
                logSection
            }
            .navigationTitle("Port Relay")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var listenSection: some View {
        Section("Listen") {
            TextField("Port", text: $listenPort)
                .keyboardType(.numberPad)
                .focused($focused, equals: .listenPort)
                .disabled(engine.isRunning)
        }
    }

    private var remoteSection: some View {
        Section("Remote") {
            TextField("Host (IP)", text: $remoteHost)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
                .focused($focused, equals: .remoteHost)
                .disabled(engine.isRunning)
                .onSubmit { focused = .remotePort }
            TextField("Port", text: $remotePort)
                .keyboardType(.numberPad)
                .focused($focused, equals: .remotePort)
                .disabled(engine.isRunning)
        }
    }

    private var protocolSection: some View {
        Section("Protocol") {
            Picker("Protocol", selection: $selectedProto) {
                ForEach(RelayProtocol.allCases, id: \.self) { proto in
                    Text(proto.rawValue).tag(proto)
                }
            }
            .pickerStyle(.segmented)
            .disabled(engine.isRunning)
        }
    }

    private var controlSection: some View {
        Section {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button(action: toggle) {
                Text(engine.isRunning ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .disabled(!engine.isRunning && pendingConfig == nil)
            .foregroundStyle(engine.isRunning ? .red : .green)
        }
    }

    private var logSection: some View {
        Section("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(engine.logs) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .frame(minHeight: 200)
                .onChange(of: engine.logs.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func toggle() {
        focused = nil
        if engine.isRunning {
            engine.stop()
            errorMessage = nil
            return
        }
        do {
            let config = try RelayConfig(
                listenPort: listenPort,
                remoteHost: remoteHost,
                remotePort: remotePort,
                proto: selectedProto
            )
            try engine.start(config: config)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
