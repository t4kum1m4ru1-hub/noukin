import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Android ネイティブ層（MainActivity.kt）と通信する MethodChannel 名
const String kKeyEventsChannelName = 'io.noukin.noukin/key_events';

/// BGM の音量を一時的に下げる（ダッキング）制御のインターフェース
abstract class AudioDuckingController {
  Future<void> configure();
  Future<void> requestDucking();
  Future<void> releaseDucking();
}

/// `audio_session` を用いて OS にオーディオフォーカス（ダッキング）を要求・解除する実装
class AudioSessionDuckingController implements AudioDuckingController {
  AudioSession? _session;
  bool _isConfigured = false;

  @override
  Future<void> configure() async {
    if (_isConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.assistanceNavigationGuidance,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      _session = session;
      _isConfigured = true;
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('AudioSessionDuckingController.configure error: $e');
    }
  }

  @override
  Future<void> requestDucking() async {
    try {
      if (!_isConfigured) {
        await configure();
      }
      await _session?.setActive(true);
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('AudioSessionDuckingController.requestDucking error: $e');
    }
  }

  @override
  Future<void> releaseDucking() async {
    try {
      await _session?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('AudioSessionDuckingController.releaseDucking error: $e');
    }
  }
}

/// 自動テスト用のインメモリダッキングコントローラ
class FakeAudioDuckingController implements AudioDuckingController {
  final List<String> events = <String>[];
  bool isConfigured = false;
  bool isCurrentlyDucked = false;

  @override
  Future<void> configure() async {
    isConfigured = true;
    events.add('configure');
  }

  @override
  Future<void> requestDucking() async {
    if (!isConfigured) {
      await configure();
    }
    isCurrentlyDucked = true;
    events.add('requestDucking');
  }

  @override
  Future<void> releaseDucking() async {
    isCurrentlyDucked = false;
    events.add('releaseDucking');
  }
}

/// 操作時の短い電子音（ビープ音）を再生するインターフェース
abstract class SoundEffectService {
  Future<void> playBeep();
}

/// Android 標準 ToneGenerator（MethodChannel 経由）＋ SystemSound フォールバックの電子音サービス
class PlatformSoundEffectService implements SoundEffectService {
  static const MethodChannel _channel = MethodChannel(kKeyEventsChannelName);
  final AudioDuckingController? duckingController;

  PlatformSoundEffectService({this.duckingController});

  @override
  Future<void> playBeep() async {
    try {
      await duckingController?.requestDucking();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<bool>('playBeep');
      }
      await SystemSound.play(SystemSoundType.click);
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('PlatformSoundEffectService.playBeep error: $e');
    }
  }
}

/// 自動テスト用のインメモリ電子音サービス
class FakeSoundEffectService implements SoundEffectService {
  int beepCount = 0;

  @override
  Future<void> playBeep() async {
    beepCount++;
  }

  void clear() {
    beepCount = 0;
  }
}

/// 音声読み上げ（TTS）機能のインターフェース
abstract class TtsService {
  Future<void> initialize();
  Future<void> speak(String text);
  Future<void> speakAndWait(String text);
  Future<void> stop();
  Future<void> setVolume(double volume) async {}
}

/// `flutter_tts` とオーディオダッキングを連携させる本番用 TTS サービス
class FlutterTtsService implements TtsService {
  final FlutterTts _flutterTts;
  final AudioDuckingController _duckingController;

  bool _isInitialized = false;
  bool _isSpeaking = false;
  bool _isDucked = false;
  Completer<void>? _cancelCompleter;
  Completer<void>? _utteranceCompleter;

  FlutterTtsService({
    FlutterTts? tts,
    AudioDuckingController? duckingController,
  }) : _flutterTts = tts ?? FlutterTts(),
       _duckingController =
           duckingController ?? AudioSessionDuckingController();

  void _completeUtterance() {
    final completer = _utteranceCompleter;
    _utteranceCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _duckingController.configure();

      await _flutterTts.setLanguage('ja-JP');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(false);

      if (defaultTargetPlatform == TargetPlatform.android) {
        await _flutterTts.setAudioAttributesForNavigation();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.autoStopSharedSession(false);
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
        );
      }

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _completeUtterance();
        unawaited(_releaseDuckingIfNeeded());
      });

      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        _completeUtterance();
        final future = _releaseDuckingIfNeeded();
        if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
          future.whenComplete(() {
            if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
              _cancelCompleter!.complete();
            }
          });
        }
      });

      _flutterTts.setErrorHandler((dynamic message) {
        debugPrint('FlutterTts errorHandler: $message');
        _isSpeaking = false;
        _completeUtterance();
        final future = _releaseDuckingIfNeeded();
        if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
          future.whenComplete(() {
            if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
              _cancelCompleter!.complete();
            }
          });
        }
      });

      _isInitialized = true;
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('FlutterTtsService.initialize error: $e');
    }
  }

  Future<void> _requestDucking() async {
    _isDucked = true;
    await _duckingController.requestDucking();
  }

  Future<void> _releaseDuckingIfNeeded() async {
    if (!_isDucked) return;
    _isDucked = false;
    await _duckingController.releaseDucking();
  }

  @override
  Future<void> speak(String text) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (_isSpeaking || _isDucked) {
        final completer = Completer<void>();
        _cancelCompleter = completer;
        _isSpeaking = false;
        _completeUtterance();
        await _flutterTts.stop();
        await completer.future.timeout(
          const Duration(milliseconds: 80),
          onTimeout: () {},
        );
        _cancelCompleter = null;
        await _releaseDuckingIfNeeded();
      }

      await _requestDucking();
      _isSpeaking = true;
      await _flutterTts.speak(text);
    } on MissingPluginException {
      _isSpeaking = false;
      _completeUtterance();
      await _releaseDuckingIfNeeded();
    } catch (e) {
      debugPrint('FlutterTtsService.speak error: $e');
      _isSpeaking = false;
      _completeUtterance();
      await _releaseDuckingIfNeeded();
    }
  }

  @override
  Future<void> speakAndWait(String text) async {
    final completer = Completer<void>();
    await speak(text);
    if (!_isSpeaking) {
      return;
    }
    _utteranceCompleter = completer;
    final timeoutMs = (text.length * 250).clamp(2000, 12000);
    await completer.future.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: _completeUtterance,
    );
  }

  @override
  Future<void> stop() async {
    try {
      _isSpeaking = false;
      _completeUtterance();
      await _flutterTts.stop();
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('FlutterTtsService.stop error: $e');
    } finally {
      await _releaseDuckingIfNeeded();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _flutterTts.setVolume(volume.clamp(0.0, 1.0));
    } on MissingPluginException {
      // テスト環境や非プラグイン環境では無視
    } catch (e) {
      debugPrint('FlutterTtsService.setVolume error: $e');
    }
  }
}

/// 自動テスト用のインメモリ TTS サービス
class FakeTtsService implements TtsService {
  final List<String> spokenHistory = <String>[];
  bool isInitialized = false;
  int stopCallCount = 0;
  double currentVolume = 1.0;

  String? get lastSpoken => spokenHistory.isNotEmpty ? spokenHistory.last : null;
  int get speakCount => spokenHistory.length;

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> speak(String text) async {
    if (!isInitialized) {
      await initialize();
    }
    spokenHistory.add(text);
  }

  @override
  Future<void> speakAndWait(String text) async {
    await speak(text);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> setVolume(double volume) async {
    currentVolume = volume;
  }

  void clear() {
    spokenHistory.clear();
  }
}

/// 検知対象の6種類の物理ボタン・イヤホンメディアキー定義
enum ButtonAction {
  volumeUp(keyCode: 24, keyName: 'KEYCODE_VOLUME_UP'),
  volumeDown(keyCode: 25, keyName: 'KEYCODE_VOLUME_DOWN'),
  mediaPlayPause(keyCode: 85, keyName: 'KEYCODE_MEDIA_PLAY_PAUSE'),
  headsetHook(keyCode: 79, keyName: 'KEYCODE_HEADSETHOOK'),
  mediaNext(keyCode: 87, keyName: 'KEYCODE_MEDIA_NEXT'),
  mediaPrevious(keyCode: 88, keyName: 'KEYCODE_MEDIA_PREVIOUS');

  final int keyCode;
  final String keyName;

  const ButtonAction({required this.keyCode, required this.keyName});

  /// Android キーコード（数値）から対応する [ButtonAction] を返す（対象外は null）
  static ButtonAction? fromKeyCode(int keyCode) {
    for (final action in ButtonAction.values) {
      if (action.keyCode == keyCode) {
        return action;
      }
    }
    return null;
  }
}

/// Android ネイティブ層からのハードウェアキーイベントを最前面のリスナーへ配信し、
/// 横取りの有効/無効を同期するディスパッチャ
class KeyEventChannelDispatcher {
  KeyEventChannelDispatcher._();

  static final KeyEventChannelDispatcher instance =
      KeyEventChannelDispatcher._();

  static const MethodChannel _channel = MethodChannel(kKeyEventsChannelName);
  final List<void Function(ButtonAction action)> _listeners =
      <void Function(ButtonAction action)>[];
  bool _isInterceptionEnabled = false;

  bool get isInterceptionEnabled => _isInterceptionEnabled;

  void registerListener(void Function(ButtonAction action) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(setInterceptionEnabled(true));
  }

  void unregisterListener(void Function(ButtonAction action) listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _channel.setMethodCallHandler(null);
      unawaited(setInterceptionEnabled(false));
    } else {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  /// トレーニング中画面がアクティブな間だけ Android 側でキー横取りを有効化する
  Future<void> setInterceptionEnabled(bool enabled) async {
    _isInterceptionEnabled = enabled;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<bool>('setKeyInterceptionEnabled', enabled);
    } on MissingPluginException {
      // テスト環境やネイティブ未接続環境では無視
    } catch (e) {
      debugPrint('KeyEventChannelDispatcher.setInterceptionEnabled error: $e');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'playBeep') {
      return true;
    }
    if (call.method != 'onKeyEvent') {
      return false;
    }

    int? keyCode;
    final args = call.arguments;
    if (args is int) {
      keyCode = args;
    } else if (args is Map) {
      final raw = args['keyCode'];
      if (raw is int) {
        keyCode = raw;
      }
    }

    if (keyCode == null) {
      return false;
    }

    final action = ButtonAction.fromKeyCode(keyCode);
    if (action == null) {
      return false;
    }

    if (_listeners.isNotEmpty) {
      _listeners.last(action);
    }
    return true;
  }
}
