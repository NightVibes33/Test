import SwiftUI
import MultipeerConnectivity

struct DrivePeerCastView: View {
    @ObservedObject var cast: DrivePeerCast
    @Environment(\.dismiss) private var dismiss
    @State private var showCompatibleViewer = false
    @State private var confirmStop = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Real receiver / viewer") {
                    Text("DriveDeck receives and sends actual video frames with nearby DriveDeck devices. Connections are encrypted and require approval. This is an original screen-cast protocol, not Apple CarPlay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Label(cast.status, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                    HStack(spacing: 12) {
                        Button("Discover / receive") { cast.start() }
                            .buttonStyle(.borderedProminent)
                        Button("Stop connections", role: .destructive) {
                            confirmStop = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Nearby DriveDeck screens") {
                    if cast.nearby.isEmpty {
                        Text("No receivers found. Open DriveDeck on a second iPhone or iPad, then choose Discover / receive.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cast.nearby, id: \.displayName) { device in
                        Button {
                            cast.invite(device)
                        } label: {
                            HStack {
                                Label(device.displayName, systemImage: "iphone.radiowaves.left.and.right")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }

                Section("Encrypted session") {
                    if cast.connectedNames.isEmpty {
                        Text("No connected peers")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cast.connectedNames, id: \.self) { name in
                        Label(name, systemImage: "lock.shield.fill")
                    }
                    Button {
                        if cast.isCapturing { cast.stopCapture() }
                        else { cast.startCapture() }
                    } label: {
                        Label(cast.isCapturing ? "Stop sending this app's screen" : "Broadcast this app's screen",
                              systemImage: cast.isCapturing ? "stop.circle.fill" : "record.circle")
                    }
                    .disabled(cast.connectedNames.isEmpty && !cast.isCapturing)
                    Text("ReplayKit captures while DriveDeck remains visible, with iOS permission. No silent recording, background recording, microphone capture, or system-wide touch injection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !cast.connectedNames.isEmpty {
                    Section("Live viewer") {
                        if let image = cast.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .accessibilityLabel("Received screen-cast frames")
                            Text("Received frames: \(cast.receivedFrameCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView("No video yet",
                                                   systemImage: "play.rectangle",
                                                   description: Text("Start ReplayKit screen sharing on the sending device."))
                        }
                        Text("Remote dashboard controls")
                            .font(.headline)
                        HStack {
                            ForEach(["Home", "Maps", "Radio", "Cluster"], id: \.self) { command in
                                Button(command) {
                                    cast.sendCommand(command)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.small)
                        Text("These controls change DriveDeck dashboard pages only. They cannot inject touches into other apps or a real CarPlay session.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Compatible CarPlay web viewer") {
                    Text("iCarCast's own receiver can serve H.264 CarPlay frames through an HTTPS browser endpoint and WSS transport. You can open an authorized receiver's actual browser viewer here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showCompatibleViewer = true
                    } label: {
                        Label("Open existing CarPlay receiver viewer", systemImage: "network")
                    }
                    Text("This feature views an externally established CarPlay session. It does not implement CarPlay authentication or become a certified head unit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Viewer & Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        cast.stop()
                        cast.start()
                    } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Restart discovery")
                }
            }
            .onAppear { cast.start() }
            .sheet(isPresented: $showCompatibleViewer) {
                ReceiverBridgeView()
            }
            .alert("Allow device to connect?", isPresented: Binding(
                get: { cast.pendingInvitation != nil },
                set: { visible in if !visible && cast.pendingInvitation != nil { cast.refuseInvitation() } }
            )) {
                Button("Accept") { cast.acceptInvitation() }
                Button("Decline", role: .cancel) { cast.refuseInvitation() }
            } message: {
                Text("Accept encrypted video connection from \(cast.pendingInvitation ?? "unknown device")?")
            }
            .confirmationDialog("Disconnect all paired screens?", isPresented: $confirmStop) {
                Button("Disconnect", role: .destructive) { cast.stop() }
            }
        }
    }
}
