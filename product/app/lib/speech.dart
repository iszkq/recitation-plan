import 'dart:async';

import 'package:flutter/services.dart';
import 'package:recitation_core/recitation_core.dart';

/// iOS 系统语音识别适配器。最终转录才会交给考核服务，临时文字只用于显示进度。
class IosSpeechProvider implements SpeechProvider {
  IosSpeechProvider() {
    _events.receiveBroadcastStream().listen(
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
          SpeechUpdate(state: SpeechState.failed, error: '$error'),
        );
      },
    );
  }

  static const _channel = MethodChannel('recitation/speech');
  static const _events = EventChannel('recitation/speech/events');
  final _controller = StreamController<SpeechUpdate>.broadcast();

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
    return SpeechUpdate(
      state: SpeechState.ready,
      finalText: result['finalText'] as String? ?? '',
      confidence: (result['confidence'] as num?)?.toDouble(),
    );
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  void dispose() {
    _controller.close();
  }
}
