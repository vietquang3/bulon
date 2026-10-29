import Foundation
import Network
import UIKit

/// Gửi nút âm lượng + joystick tới PC qua UDP (cổng 9876).
///   iPhone -> PC : "H"                       chào / giữ kết nối (mỗi 2 giây)
///                  "B" + ("U"|"D") + seq     Vol+ / Vol-   (mỗi lần bấm gửi 2 gói, PC bỏ gói trùng theo seq)
///                  "M" + ("L"|"R"|"N")       joystick trái / phải / thả (gửi lặp mỗi 0.1s khi đang kéo; PC: A / D)
///   PC -> iPhone : "PONG|ok", "EV|nội dung", "MSG|nội dung"
final class UDPClient: ObservableObject {
    @Published var connected = false
    @Published var status = "Chưa kết nối"
    @Published var lastEvent = ""

    private var connection: NWConnection?
    private var receiving = false
    private var seq: UInt8 = 0
    private var timer: Timer?
    private var moveTimer: Timer?
    private var lastRx = Date.distantPast
    private let queue = DispatchQueue(label: "boxcontroller.udp")

    func connect(host: String, port: UInt16 = 9876) {
        disconnect()
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, let p = NWEndpoint.Port(rawValue: port) else {
            status = "Hãy nhập IP của PC"
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(h), port: p, using: .udp)
        connection = conn
        receiving = false
        status = "Đang kết nối…"
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.status = "Đang chờ PC trả lời…"
                    self.sendHello()
                    if !self.receiving {
                        self.receiving = true
                        self.receiveLoop(conn)
                    }
                case .failed(let e):
                    self.status = "Lỗi: \(e.localizedDescription)"
                case .waiting(let e):
                    self.status = "Chờ mạng: \(e.localizedDescription)"
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func disconnect() {
        moveTimer?.invalidate()
        moveTimer = nil
        timer?.invalidate()
        timer = nil
        connection?.cancel()
        connection = nil
        receiving = false
        connected = false
    }

    private func tick() {
        sendHello()
        if connected && Date().timeIntervalSince(lastRx) > 5 {
            connected = false
            status = "Mất kết nối PC (kiểm tra IP / tường lửa)"
        }
    }

    private func sendHello() {
        send(Data("H".utf8))
    }

    /// up = true -> Vol+ (PC: S) ; up = false -> Vol- (PC: W)
    func sendButton(up: Bool) {
        seq = seq &+ 1
        let packet = Data([0x42, up ? 0x55 : 0x44, seq])   // 'B', 'U'/'D', seq
        send(packet)
        queue.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            self?.send(packet)                               // gửi lần 2 phòng rớt gói
        }
    }

    /// Joystick: dir = -1 kéo trái (PC: A) ; 0 thả cần ; 1 kéo phải (PC: D)
    /// Khi đang kéo, gửi lặp mỗi 0.1s để PC giữ phím; PC tự nhả nếu mất tín hiệu.
    func setMove(_ dir: Int) {
        moveTimer?.invalidate()
        moveTimer = nil
        sendMove(dir)
        if dir == 0 {
            queue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.sendMove(0)                            // gửi lần 2 phòng rớt gói 'thả'
            }
        } else {
            moveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.sendMove(dir)
            }
        }
    }

    private func sendMove(_ dir: Int) {
        let code: UInt8 = dir < 0 ? 0x4C : (dir > 0 ? 0x52 : 0x4E)   // 'L' / 'R' / 'N'
        send(Data([0x4D, code]))                                       // 'M' + mã
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, self.connection === conn else { return }
            if let data = data, let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { self.handle(text) }
            }
            if error == nil {
                self.receiveLoop(conn)
            }
        }
    }

    private func handle(_ text: String) {
        lastRx = Date()
        if !connected { connected = true }
        status = "Đã kết nối PC ✓"
        for raw in text.split(separator: "\n") {
            let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let kind = String(parts[0])
            let body = String(parts[1])
            if kind == "EV" || kind == "HIT" || kind == "MSG" {
                lastEvent = body
            }
        }
    }
}