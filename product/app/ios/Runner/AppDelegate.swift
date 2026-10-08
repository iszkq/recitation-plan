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
  private var lastText = ""

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
    let events = FlutterEventChannel(name: "recitation/speech/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ state: String, interim: String = "", finalText: String? = nil, confidence: Float? = nil, error: String? = nil) {
    var value: [String: Any] = ["state": state, "interimText": interim]
    if let finalText { value["finalText"] = finalText }
    if let confidence { value["confidence"] = confidence }
    if let error { value["error"] = error }
    DispatchQueue.main.async { self.sink?(value) }
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { speechStatus in
      guard speechStatus == .authorized else { result(false); return }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  private func start(locale: String, result: @escaping FlutterResult) {
    cancel()
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
      emit("unavailable", error: "当前设备暂不支持中文语音识别")
      result(FlutterError(code: "UNAVAILABLE", message: "当前设备暂不支持中文语音识别", details: nil))
      return
    }
    self.recognizer = recognizer
    let audio = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = false
    self.engine = audio
    self.request = request
    self.lastText = ""
    let input = audio.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      audio.prepare()
      try audio.start()
    } catch {
      cancel()
      emit("failed", error: "麦克风启动失败，请检查系统权限")
      result(FlutterError(code: "AUDIO", message: error.localizedDescription, details: nil))
      return
    }
    task = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
      guard let self else { return }
      if let recognition {
        let text = recognition.bestTranscription.formattedString
        self.lastText = text
        self.emit(recognition.isFinal ? "finalizing" : "recording", interim: text)
        if recognition.isFinal { self.finishStop(text: text, confidence: recognition.bestTranscription.segments.last?.confidence) }
      }
      if let error, self.stopResult != nil {
        self.emit("failed", error: "语音识别失败，请重试")
        self.stopResult?(FlutterError(code: "RECOGNITION", message: error.localizedDescription, details: nil))
        self.stopResult = nil
      }
    }
    emit("recording")
    result(nil)
  }

  private func stop(_ result: @escaping FlutterResult) {
    guard task != nil else { result(["finalText": lastText]); return }
    stopResult = result
    emit("finalizing", interim: lastText)
    engine?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
  }

  private func finishStop(text: String, confidence: Float?) {
    let callback = stopResult
    stopResult = nil
    emit("ready", finalText: text, confidence: confidence)
    callback?(["finalText": text, "confidence": confidence ?? 0])
    task = nil
    request = nil
    engine = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func cancel() {
    engine?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    engine = nil
    request = nil
    task = nil
    stopResult = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
    speech.register(on: engineBridge.binaryMessenger)
  }
}
