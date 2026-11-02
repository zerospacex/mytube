import UIKit
import Flutter
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var mediaChannel: FlutterMethodChannel?
  private var commandTargets: [(MPRemoteCommand, Any)] = []
  private var hasMedia = false
  private var playing = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "mytube/background", binaryMessenger: controller.binaryMessenger)
      mediaChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(FlutterMethodNotImplemented); return }
        do {
          switch call.method {
          case "updateMedia":
            try self.updateMedia(call.arguments as? [String: Any] ?? [:])
          case "clearMedia":
            self.clearMedia()
          default:
            result(FlutterMethodNotImplemented)
            return
          }
          result(nil)
        } catch {
          result(FlutterError(code: "media_controls_failed", message: error.localizedDescription, details: nil))
        }
      }
      installCommands()
    }
    return launched
  }

  private func installCommands() {
    let center = MPRemoteCommandCenter.shared()
    let actions: [(MPRemoteCommand, String)] = [
      (center.playCommand, "play"), (center.pauseCommand, "pause"),
      (center.togglePlayPauseCommand, "toggle"),
      (center.nextTrackCommand, "next"), (center.previousTrackCommand, "previous"),
      (center.changePlaybackPositionCommand, "seek")
    ]
    for (command, action) in actions {
      command.isEnabled = false
      let target = command.addTarget { [weak self] event in
        guard let self = self, self.hasMedia, let channel = self.mediaChannel else { return .noSuchContent }
        var arguments: [String: Any] = ["action": action]
        if let seek = event as? MPChangePlaybackPositionCommandEvent { arguments["position"] = seek.positionTime }
        DispatchQueue.main.async {
          channel.invokeMethod("mediaCommand", arguments: arguments)
        }
        return .success
      }
      commandTargets.append((command, target))
    }
  }

  private func updateMedia(_ state: [String: Any]) throws {
    guard state["hasMedia"] as? Bool == true else { clearMedia(); return }
    let nextPlaying = state["playing"] as? Bool == true
    if !hasMedia && !nextPlaying { return }
    if nextPlaying && !playing {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playback, mode: .default)
      try audio.setActive(true)
    }
    hasMedia = true
    playing = nextPlaying
    for (command, _) in commandTargets { command.isEnabled = true }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: state["trackTitle"] as? String ?? "MyTube Music",
      MPMediaItemPropertyArtist: state["artist"] as? String ?? "",
      MPMediaItemPropertyPlaybackDuration: (state["duration"] as? Double ?? 0) / 1000,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: (state["position"] as? Double ?? 0) / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
    ]
  }

  private func clearMedia() {
    let wasActive = hasMedia
    hasMedia = false
    playing = false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    for (command, _) in commandTargets { command.isEnabled = false }
    if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    clearMedia()
    for (command, target) in commandTargets { command.removeTarget(target) }
    mediaChannel?.setMethodCallHandler(nil)
    super.applicationWillTerminate(application)
  }
}
