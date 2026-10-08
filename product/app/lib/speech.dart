import 'dart:async';

import 'package:flutter/services.dart';
import 'package:recitation_core/recitation_core.dart';

/// iOS 系统语音识别适配器。最终转录才会交给考核服务，临时文字只用于显示进度。
class IosSpeechProvider implements SpeechProvider {
  IosSpeechProvider() {
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        final data = Map<String, dynamic>.from(event as Map);
        final state = switch (data['state']) {
          'recording' => SpeechState.recording,
          'finalizing' => SpeechState.finalizing,
          'ready' => SpeechState.ready,
          'unavailable' => SpeechState.unavailable,
          'failed' => SpeechState.failed,
          _ => SpeechState.idle,
        };
        _controller.add(
          SpeechUpdate(
            state: state,
            interimText: (data['interimText'] as String?) ?? '',
            finalText: data['finalText'] as String?,
            confidence: (data['confidence'] as num?)?.toDouble(),
            error: data['error'] as String?,
          ),
        );
      },
      onError: (Object error) {
        _controller.add(
          const SpeechUpdate(
            state: SpeechState.failed,
            error: '语音识别暂不可用，请重试或使用文字考核',
          ),
        );
      },
    );
  }

  static const _channel = MethodChannel('recitation/speech');
  static const _events = EventChannel('recitation/speech/events');
  final _controller = StreamController<SpeechUpdate>.broadcast();
  late final StreamSubscription<dynamic> _subscription;

  @override
  Stream<SpeechUpdate> get updates => _controller.stream;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<void> start({required String locale}) async {
    await _channel.invokeMethod<void>('start', {'locale': locale});
  }

  @override
  Future<SpeechUpdate> stopAndFinalize() async {
    final result = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<dynamic, dynamic>>('stop') ?? {},
    );
    if (result['finalText'] is! String) {
      throw StateError('未收到最终转录，请重新录音');
    }
    return SpeechUpdate(
      state: SpeechState.ready,
      finalText: result['finalText'] as String,
      confidence: (result['confidence'] as num?)?.toDouble(),
    );
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }
}
