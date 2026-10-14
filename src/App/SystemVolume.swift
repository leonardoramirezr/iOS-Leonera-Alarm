import AVFoundation
import MediaPlayer
import UIKit

/// Keeps the iPhone's volume all the way up while the alarm rings inside the app, and
/// puts it back where it was afterwards.
///
/// iOS has no public API for this: it moves the slider of a hidden MPVolumeView, the
/// workaround alarm apps have used for years. It changes the volume the buttons control
/// while something plays, not «Tono y alertas», which is what AlarmKit alarms follow on
/// the lock screen. If an iOS update breaks it, the alarm still rings, at the volume
/// that was set.
@MainActor
final class SystemVolume {
    private var volumeView: MPVolumeView?
    private var observation: NSKeyValueObservation?
    private var isHolding = false
    /// The speaker's volume before the alarm raised it.
    private var restoreTo: Float?

    /// Nonisolated so it can be a stored property's default value.
    nonisolated init() {}

    /// Turns the volume all the way up and, if it is lowered with the buttons, raises it
    /// again. Only on the iPhone's own speaker: full volume in headphones could hurt.
    func holdAtMaximum() {
        guard !isHolding else { return }
        isHolding = true
        attachVolumeView()
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { @Sendable [weak self] _, change in
            guard let volume = change.newValue, volume < 0.99 else { return }
            Task { @MainActor in self?.raise() }
        }
        raise()
    }

    /// Puts the volume back where it was before the alarm.
    func release() {
        guard isHolding else { return }
        isHolding = false
        observation?.invalidate()
        observation = nil
        if let restoreTo, Self.isOnSpeaker {
            set(restoreTo)
        }
        restoreTo = nil
        // Removed once the volume is back in place.
        let view = volumeView
        volumeView = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            view?.removeFromSuperview()
        }
    }

    private func raise() {
        guard isHolding, Self.isOnSpeaker else { return }
        if restoreTo == nil {
            restoreTo = AVAudioSession.sharedInstance().outputVolume
        }
        set(1)
    }

    private func set(_ value: Float) {
        guard let slider = volumeView?.subviews.lazy.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = value
        // Right after the view is created the slider can ignore it, so once more in a moment.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            slider.value = value
        }
    }

    /// Off screen and almost transparent, but in a window: that is where it works most
    /// reliably, and while it is there iOS usually doesn't show its volume indicator.
    private func attachVolumeView() {
        guard volumeView == nil else { return }
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        Self.keyWindow?.addSubview(view)
        volumeView = view
    }

    private static var isOnSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }
}
