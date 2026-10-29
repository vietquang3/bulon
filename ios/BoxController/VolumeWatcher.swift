import AVFoundation
import MediaPlayer
import SwiftUI

/// Bắt nút Vol+ / Vol- vật lý.
/// Cách làm: theo dõi AVAudioSession.outputVolume; mỗi lần âm lượng lệch khỏi mốc 0.5 thì coi là 1 lần bấm
/// rồi đặt lại về 0.5 (nhờ vậy bấm bao nhiêu lần cũng không chạm trần/đáy 0%/100%).
/// Phát âm thanh im lặng để app vẫn nhận nút khi màn hình tối.
final class VolumeWatcher: ObservableObject {
    /// true = Vol+, false = Vol-
    var onPress: ((Bool) -> Void)?
    weak var volumeView: MPVolumeView?

    private let session = AVAudioSession.sharedInstance()
    private var observation: NSKeyValueObservation?
    private var player: AVAudioPlayer?
    private let center: Float = 0.5

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    func start() {
        activateSession()
        startSilentLoop()
        if observation == nil {
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let v = change.newValue else { return }
                DispatchQueue.main.async { self?.volumeChanged(v) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.recenter()
        }
    }

    /// Gọi khi app quay lại foreground / sau cuộc gọi.
    func resume() {
        activateSession()
        if player?.isPlaying == false { player?.play() }
        recenter()
    }

    private func activateSession() {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session lỗi: \(error)")
        }
    }

    private func volumeChanged(_ v: Float) {
        if abs(v - center) < 0.02 { return }       // chính là lần mình tự đặt lại về giữa
        onPress?(v > center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.recenter()
        }
    }

    private func recenter() {
        slider?.value = center
    }

    private func startSilentLoop() {
        if player != nil { return }
        let sampleRate = 8000
        let n = sampleRate                              // 1 giây im lặng, mono 16-bit
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        var wav = Data()
        wav.append(Data("RIFF".utf8))
        wav.append(le32(UInt32(36 + n * 2)))
        wav.append(Data("WAVE".utf8))
        wav.append(Data("fmt ".utf8))
        wav.append(le32(16))
        wav.append(le16(1))                             // PCM
        wav.append(le16(1))                             // mono
        wav.append(le32(UInt32(sampleRate)))
        wav.append(le32(UInt32(sampleRate * 2)))
        wav.append(le16(2))
        wav.append(le16(16))
        wav.append(Data("data".utf8))
        wav.append(le32(UInt32(n * 2)))
        wav.append(Data(count: n * 2))
        player = try? AVAudioPlayer(data: wav)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        player?.play()
    }
}

/// MPVolumeView ẩn: cần có trong màn hình để (1) đặt lại âm lượng về giữa, (2) iOS không hiện khung âm lượng che màn hình.
struct VolumeHost: UIViewRepresentable {
    let watcher: VolumeWatcher

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.alpha = 0.01
        watcher.volumeView = v
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
