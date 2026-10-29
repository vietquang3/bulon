import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var net = UDPClient()
    @StateObject private var vol = VolumeWatcher()
    @AppStorage("pcHost") private var host: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var flash = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("BOX CONTROLLER")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Vol+  →  S        Vol−  →  W")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)

                HStack(spacing: 10) {
                    TextField("IP của PC, vd 192.168.1.5", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(Color(white: 0.16))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    Button("Kết nối") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        net.connect(host: host)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Text(net.status)
                    .font(.subheadline)
                    .foregroundColor(net.connected ? .green : .orange)

                Text(flash.isEmpty ? (net.lastEvent.isEmpty ? "—" : net.lastEvent) : flash)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(flash.isEmpty ? .white : .yellow)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)

                HStack(spacing: 14) {
                    bigButton(title: "S", sub: "Vol+") { press(up: true) }
                    bigButton(title: "W", sub: "Vol−") { press(up: false) }
                }

                Text("Để màn hình sáng, rồi bấm nút âm lượng bên hông máy. Hai nút trên màn hình dùng để thử.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(20)
        }
        .background(VolumeHost(watcher: vol).frame(width: 1, height: 1))
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            vol.onPress = { up in
                DispatchQueue.main.async { press(up: up) }
            }
            vol.start()
            if !host.isEmpty { net.connect(host: host) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { vol.resume() }
        }
    }

    private func press(up: Bool) {
        net.sendButton(up: up)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flash = up ? "S  (Vol+)" : "W  (Vol−)"
        let mark = flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if flash == mark { flash = "" }
        }
    }

    private func bigButton(title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 44, weight: .black, design: .rounded))
                Text(sub).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color(white: 0.18))
            .foregroundColor(.white)
            .cornerRadius(16)
        }
    }
}
