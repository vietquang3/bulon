import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var net = UDPClient()
    @StateObject private var vol = VolumeWatcher()
    @AppStorage("pcHost") private var host: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var flash = ""
    @State private var kDown = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("BOX CONTROLLER")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Vol+  →  W      Vol−  →  S      Chạm ô K  →  K")
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

                kPad

                HStack(spacing: 14) {
                    bigButton(title: "W", sub: "Vol+") { press(up: true) }
                    bigButton(title: "S", sub: "Vol−") { press(up: false) }
                }

                Text("Để màn hình sáng, bấm nút âm lượng bên hông máy. Chạm ô K để nhảy. Hai nút W/S trên màn hình dùng để thử.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
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

    /// Ô K lớn: gửi ngay khi ngón tay chạm xuống (không đợi nhả)
    private var kPad: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(kDown ? Color.blue : Color(white: 0.18))
            .overlay(
                VStack(spacing: 4) {
                    Text("K").font(.system(size: 64, weight: .black, design: .rounded))
                    Text("chạm để nhảy").font(.caption)
                }
                .foregroundColor(.white)
            )
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !kDown else { return }
                        kDown = true
                        pressK()
                    }
                    .onEnded { _ in kDown = false }
            )
    }

    private func pressK() {
        net.sendK()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        flash = "K  (nhảy)"
        let mark = flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if flash == mark { flash = "" }
        }
    }

    private func press(up: Bool) {
        net.sendButton(up: up)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flash = up ? "W  (Vol+)" : "S  (Vol−)"
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