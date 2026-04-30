import SwiftUI

struct RelayView: View {
    @State private var engine = RelayEngine()
    @AppStorage("listenPort") private var listenPort = ""
    @AppStorage("remoteHost") private var remoteHost = ""
    @AppStorage("remotePort") private var remotePort = ""
    @AppStorage("selectedProto") private var selectedProto: RelayProtocol = .udp
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field: Hashable { case listenPort, remoteHost, remotePort }

    private var isInputValid: Bool {
        guard let lp = UInt16(listenPort), lp > 0,
              let rp = UInt16(remotePort), rp > 0,
              !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return true
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
                ForEach(RelayProtocol.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
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
            Button {
                toggle()
            } label: {
                Text(engine.isRunning ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .disabled(!engine.isRunning && !isInputValid)
            .foregroundStyle(engine.isRunning ? .red : .green)
        }
    }

    private var logSection: some View {
        Section("Log") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(engine.logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .id(i)
                        }
                    }
                }
                .frame(minHeight: 200)
                .onChange(of: engine.logs.count) {
                    if let last = engine.logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
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

        switch RelayConfig.validate(listenPort: listenPort, remoteHost: remoteHost, remotePort: remotePort) {
        case .success(let (lp, host, rp)):
            errorMessage = nil
            let config = RelayConfig(listenPort: lp, remoteHost: host, remotePort: rp, proto: selectedProto)
            engine.start(config: config)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
