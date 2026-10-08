import Flutter
import UIKit
import Speech
import AVFoundation

final class RecitationSpeechBridge: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var engine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var stopResult: FlutterResult?
  private var stopTimeout: DispatchWorkItem?
  private var sessionID = UUID()
  private var tapInstalled = false
  private var finalValue: [String: Any]?

  func register(on messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "recitation/speech", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "requestPermission": self.requestPermission(result)
      case "start":
        let locale = (call.arguments as? [String: Any])?["locale"] as? String ?? "zh-CN"
        self.start(locale: locale, result: result)
      case "stop": self.stop(result)
      case "cancel": self.cancel(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "recitation/speech/events", binaryMessenger: messenger)
      .setStreamHandler(self)
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted),
      name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    cancel()
    return nil
  }

  private func emit(_ state: String, interim: String = "", finalText: String? = nil,
                    confidence: Float? = nil, error: String? = nil) {
    var value: [String: Any] = ["state": state, "interimText": interim]
    if let finalText { value["finalText"] = finalText }
    if let confidence { value["confidence"] = confidence }
    if let error { value["error"] = error }
    sink?(value)
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result(false) }
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  private func start(locale: String, result: @escaping FlutterResult) {
    cancel()
    finalValue = nil
    guard SFSpeechRecognizer.authorizationStatus() == .authorized,
          AVAudioSession.sharedInstance().recordPermission == .granted else {
      result(FlutterError(code: "PERMISSION", message: "请允许麦克风和语音识别权限后重试", details: nil))
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
      emit("unavailable", error: "语音识别暂不可用，请检查网络后重试")
      result(FlutterError(code: "UNAVAILABLE", message: "语音识别暂不可用，请检查网络后重试", details: nil))
      return
    }
    self.recognizer = recognizer
    let audio = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.engine = audio
    self.request = request
    let identity = sessionID
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true)
      let input = audio.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        fail(code: "AUDIO", message: "未检测到可用麦克风，请检查音频设备后重试")
        result(FlutterError(code: "AUDIO", message: "未检测到可用麦克风", details: nil))
        return
      }
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
      }
      tapInstalled = true
      task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
        DispatchQueue.main.async {
          guard let self, self.sessionID == identity else { return }
          if let recognition {
            let text = recognition.bestTranscription.formattedString
            if recognition.isFinal {
              self.complete(text: text, confidence: recognition.bestTranscription.segments.last?.confidence)
              return
            }
            self.emit(self.stopResult == nil ? "recording" : "finalizing", interim: text)
          }
          if error != nil { self.fail(code: "RECOGNITION", message: "语音识别中断，请检查网络后重新背诵") }
        }
      }
      audio.prepare()
      try audio.start()
      emit("recording")
      result(nil)
    } catch {
      fail(code: "AUDIO", message: "麦克风启动失败，请检查系统权限后重试")
      result(FlutterError(code: "AUDIO", message: "麦克风启动失败，请重试", details: nil))
    }
  }

  private func stop(_ result: @escaping FlutterResult) {
    if let finalValue { result(finalValue); return }
    guard task != nil, stopResult == nil else {
      result(FlutterError(code: "NOT_RECORDING", message: "没有可校对的最终转录，请重新录音", details: nil))
      return
    }
    stopResult = result
    emit("finalizing")
    stopAudio()
    request?.endAudio()
    let timeout = DispatchWorkItem { [weak self] in
      self?.fail(code: "TIMEOUT", message: "等待最终转录超时，请检查网络后重试")
    }
    stopTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
  }

  private func complete(text: String, confidence: Float?) {
    let callback = stopResult
    stopResult = nil
    var value: [String: Any] = ["finalText": text]
    if let confidence { value["confidence"] = confidence }
    finalValue = value
    releaseAudio()
    emit("ready", finalText: text, confidence: confidence)
    callback?(value)
  }

  private func fail(code: String, message: String) {
    let callback = stopResult
    stopResult = nil
    finalValue = nil
    releaseAudio()
    emit("failed", error: message)
    callback?(FlutterError(code: code, message: message, details: nil))
  }

  private func stopAudio() {
    engine?.stop()
    if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
  }

  private func releaseAudio() {
    sessionID = UUID() // Ignore callbacks from the previous recognition session.
    stopTimeout?.cancel()
    stopTimeout = nil
    stopAudio()
    request?.endAudio()
    task?.cancel()
    engine = nil
    request = nil
    task = nil
    recognizer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func cancel() {
    let callback = stopResult
    stopResult = nil
    finalValue = nil
    releaseAudio()
    callback?(FlutterError(code: "CANCELLED", message: "本次录音已中断，请重新背诵", details: nil))
  }

  @objc private func interrupted(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          raw == AVAudioSession.InterruptionType.began.rawValue else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.engine != nil else { return }
      self.fail(code: "INTERRUPTED", message: "录音被来电或音频设备中断，请重新背诵")
    }
  }

  @objc private func backgrounded() {
    if engine != nil { fail(code: "BACKGROUND", message: "录音已停止，请回到考核页重新背诵") }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let speech = RecitationSpeechBridge()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    speech.register(on: engineBridge.applicationRegistrar.messenger())
  }
}
