import SwiftUI
import UIKit

/// Giao diện NGANG, chiếm trọn màn hình:
///   bên trái  : vùng joystick lớn (chạm đâu, cần hiện đó) -> A / D
///   bên phải  : IP + Kết nối, trạng thái, W / S (Vol+ / Vol-)
struct ContentView: View {
    @StateObject private var net = UDPClient()
    @StateObject private var vol = VolumeWatcher()
    @AppStorage("pcHost") private var host: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var flash = ""

    // joystick kiểu MOBA
    @State private var joyActive = false
    @State private var joyOrigin = CGPoint.zero      // chỗ ngón tay chạm xuống = tâm cần
    @State private var joyOffset: CGFloat = 0        // độ lệch ngang của núm
    @State private var moveDir = 0                   // -1 trái (A) | 0 dừng | 1 phải (D)

    private let joyRadius: CGFloat = 100
    private let joyDead: CGFloat = 30                // kéo quá ngần này mới tính

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: 12) {
                joystick
                sidePanel
                    .frame(width: 270)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .statusBar(hidden: true)
        .modifier(HideSystemOverlays())
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
            if phase == .active {
                vol.resume()
            } else {
                resetJoystick()                      // rời app thì thả cần, tránh kẹt phím
            }
        }
    }

    // MARK: - Cột bên phải

    private var sidePanel: some View {
        VStack(spacing: 8) {
            Text("BOX CONTROLLER")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("Cần → A/D   Vol+ → W   Vol− → S")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            TextField("IP của PC, vd 192.168.1.5", text: $host)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(9)
                .background(Color(white: 0.16))
                .cornerRadius(8)
                .foregroundColor(.white)

            Button(action: {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
                net.connect(host: host)
            }) {
                Text("Kết nối")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Text(net.status)
                .font(.footnote)
                .foregroundColor(net.connected ? .green : .orange)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(flash.isEmpty ? (net.lastEvent.isEmpty ? "—" : net.lastEvent) : flash)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(flash.isEmpty ? .white : .yellow)
                .frame(maxWidth: .infinity, minHeight: 36)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                bigButton(title: "W", sub: "Vol+") { press(up: true) }
                bigButton(title: "S", sub: "Vol−") { press(up: false) }
            }
            Text("Hai nút W/S để thử. Dùng nút âm lượng bên hông máy khi chơi.")
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Joystick (cảm ứng nổi: chạm đâu, cần xuất hiện đó)

    private var joystick: some View {
        GeometryReader { geo in
            let home = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let center = joyActive ? joyOrigin : home
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.10))

                // đế cần
                Circle()
                    .fill(Color.white.opacity(joyActive ? 0.14 : 0.07))
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 2))
                    .frame(width: joyRadius * 2, height: joyRadius * 2)
                    .position(center)

                // chữ A / D hai bên đế
                Text("A")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(moveDir < 0 ? .yellow : Color.white.opacity(0.45))
                    .position(x: center.x - joyRadius + 28, y: center.y)
                Text("D")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(moveDir > 0 ? .yellow : Color.white.opacity(0.45))
                    .position(x: center.x + joyRadius - 28, y: center.y)

                // núm cần
                Circle()
                    .fill(joyActive ? Color.blue : Color(white: 0.5))
                    .frame(width: 70, height: 70)
                    .shadow(radius: joyActive ? 6 : 0)
                    .position(x: center.x + joyOffset, y: center.y)

                if !joyActive {
                    Text("Đặt ngón tay vào đây rồi kéo trái / phải")
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.4))
                        .position(x: home.x, y: geo.size.height - 22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !joyActive {
                            joyActive = true
                            joyOrigin = v.startLocation
                        }
                        let dx = max(-joyRadius, min(joyRadius, v.location.x - v.startLocation.x))
                        joyOffset = dx
                        setDir(dx > joyDead ? 1 : (dx < -joyDead ? -1 : 0))
                    }
                    .onEnded { _ in resetJoystick() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setDir(_ d: Int) {
        guard d != moveDir else { return }
        moveDir = d
        net.setMove(d)
        if d != 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        flash = d < 0 ? "A  ◀" : (d > 0 ? "D  ▶" : "")
    }

    private func resetJoystick() {
        joyActive = false
        joyOffset = 0
        if moveDir != 0 {
            moveDir = 0
            net.setMove(0)
            flash = ""
        }
    }

    // MARK: - Nút Vol

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
            VStack(spacing: 2) {
                Text(title).font(.system(size: 34, weight: .black, design: .rounded))
                Text(sub).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color(white: 0.18))
            .foregroundColor(.white)
            .cornerRadius(14)
        }
    }
}

/// Ẩn thanh Home (iOS 16+) để màn hình thật sự trọn vẹn; iOS 15 bỏ qua.
struct HideSystemOverlays: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
    }
}
