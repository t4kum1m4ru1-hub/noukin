import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/models.dart';
import '../services/earphone_audio_service.dart';

/// イヤホン操作を含むトレーニング中画面の3つのモード状態
enum TrainingMode {
  /// 状態A：通常モード（トレーニング中）
  normal,

  /// 状態B：調整モード・階層1（調整項目の選択）
  adjustSelect,

  /// 状態C：調整モード・階層2（数値・値の調整）
  adjustValue,
}

/// 調整モードで選択・変更対象となる4項目（画面の上からの並び順）
enum AdjustmentTarget {
  exercise('種目名'),
  weight('重量'),
  reps('レップ数'),
  sets('セット数');

  final String label;
  const AdjustmentTarget(this.label);
}

/// トレーニング中画面（Screen A2）の状態・種目進行・数値調整・イヤホン操作を管理するコントローラ
class TrainingSessionController extends ChangeNotifier {
  static const double weightStepKg = 2.5;
  static const double minWeightKg = 2.5;
  static const int minReps = 1;
  static const int minSets = 1;
  static const Duration kDebounceDuration = Duration(milliseconds: 700);

  final MenuGenerationResult menuResult;
  final VoidCallback? onWorkoutCompleted;
  final TtsService? ttsService;
  final SoundEffectService? soundEffectService;

  late final List<PrescribedExercise> _exercises;
  int _currentIndex = 0;
  bool _isStarted = false;
  TrainingMode _mode = TrainingMode.normal;
  AdjustmentTarget _selectedTarget = AdjustmentTarget.exercise;
  int _candidateExerciseIndex = 0;
  Timer? _debounceTimer;
  Timer? _framePumpTimer;

  TrainingSessionController({
    required this.menuResult,
    this.onWorkoutCompleted,
    this.ttsService,
    this.soundEffectService,
  }) : _exercises = menuResult.exercises
           .map(_sanitizeExercise)
           .toList(growable: true);

  static PrescribedExercise _sanitizeExercise(PrescribedExercise exercise) {
    final sanitizedWeight =
        (!exercise.weightKg.isFinite || exercise.weightKg < minWeightKg)
        ? minWeightKg
        : exercise.weightKg;
    final sanitizedReps = math.max(minReps, exercise.reps);
    final sanitizedSets = math.max(minSets, exercise.sets);
    if (sanitizedWeight == exercise.weightKg &&
        sanitizedReps == exercise.reps &&
        sanitizedSets == exercise.sets) {
      return exercise;
    }
    return exercise.copyWith(
      weightKg: sanitizedWeight,
      reps: sanitizedReps,
      sets: sanitizedSets,
    );
  }

  /// テストや単体利用向けに種目リストから直接生成するファクトリ
  factory TrainingSessionController.fromExercises({
    required List<PrescribedExercise> exercises,
    TimeSlot timeSlot = TimeSlot.evening,
    WorkoutDurationCourse? course,
    WorkoutCondition? condition,
    DateTime? generatedAt,
    String? focusMuscleId,
    VoidCallback? onWorkoutCompleted,
    TtsService? ttsService,
    SoundEffectService? soundEffectService,
  }) {
    return TrainingSessionController(
      menuResult: MenuGenerationResult(
        exercises: exercises,
        muscleScores: const <String, MuscleScoreInfo>{},
        timeSlot: timeSlot,
        course: course,
        condition: condition,
        generatedAt: generatedAt,
        focusMuscleId: focusMuscleId,
      ),
      onWorkoutCompleted: onWorkoutCompleted,
      ttsService: ttsService,
      soundEffectService: soundEffectService,
    );
  }

  List<PrescribedExercise> get exercises =>
      List<PrescribedExercise>.unmodifiable(_exercises);

  int get currentIndex => _currentIndex;
  int get currentExerciseIndex => _currentIndex;
  int get candidateExerciseIndex => _candidateExerciseIndex;
  int get totalCount => _exercises.length;
  bool get isEmpty => _exercises.isEmpty;
  bool get isStarted => _isStarted;
  TrainingMode get mode => _mode;
  AdjustmentTarget get selectedTarget => _selectedTarget;
  bool get hasPendingDebounce => _debounceTimer?.isActive ?? false;
  bool get isLastExercise =>
      _exercises.isNotEmpty && _currentIndex >= _exercises.length - 1;

  PrescribedExercise get currentExercise {
    if (_exercises.isEmpty) {
      throw StateError('TrainingSessionController has no exercises');
    }
    return _exercises[_currentIndex];
  }

  PrescribedExercise? get currentExerciseOrNull =>
      (_exercises.isEmpty ||
              _currentIndex < 0 ||
              _currentIndex >= _exercises.length)
          ? null
          : _exercises[_currentIndex];

  /// 現在画面に表示すべき種目（状態Cで種目名を調整中の場合はプレビュー候補を返す）
  PrescribedExercise? get displayedExerciseOrNull {
    if (_exercises.isEmpty) return null;
    if (_mode == TrainingMode.adjustValue &&
        _selectedTarget == AdjustmentTarget.exercise &&
        _candidateExerciseIndex >= 0 &&
        _candidateExerciseIndex < _exercises.length) {
      return _exercises[_candidateExerciseIndex];
    }
    return currentExerciseOrNull;
  }

  int get _activeAdjustmentIndex {
    if (_mode == TrainingMode.adjustValue &&
        _selectedTarget == AdjustmentTarget.exercise &&
        _candidateExerciseIndex >= 0 &&
        _candidateExerciseIndex < _exercises.length) {
      return _candidateExerciseIndex;
    }
    return _currentIndex;
  }

  double get weightKg => displayedExerciseOrNull?.weightKg ?? minWeightKg;
  int get reps => displayedExerciseOrNull?.reps ?? minReps;
  int get sets => displayedExerciseOrNull?.sets ?? minSets;

  String get progressText => _exercises.isEmpty
      ? '0 / 0'
      : '${_currentIndex + 1} / ${_exercises.length}';

  /// 整数なら小数点なし（60）、小数ありなら小数第1位まで（62.5）でフォーマットする
  static String formatWeightNumber(double val) {
    if (!val.isFinite || val <= 0) return '2.5';
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  String get formattedWeightDisplay => '${formatWeightNumber(weightKg)} kg';

  /// 現在の種目の読み上げサマリー文言（例: "ベンチプレス、60kg、10回、3セット"）
  String get currentSummarySpeech {
    final ex = displayedExerciseOrNull;
    if (ex == null) return '';
    return '${ex.machine.name}、${formatWeightNumber(ex.weightKg)}kg、${ex.reps}回、${ex.sets}セット';
  }

  /// 選択中項目の現在値読み上げ文言
  String speechForTargetValue(AdjustmentTarget target) {
    final ex = displayedExerciseOrNull;
    if (ex == null) return '';
    switch (target) {
      case AdjustmentTarget.exercise:
        return ex.machine.name;
      case AdjustmentTarget.weight:
        return '${formatWeightNumber(ex.weightKg)}kg';
      case AdjustmentTarget.reps:
        return '${ex.reps}回';
      case AdjustmentTarget.sets:
        return '${ex.sets}セット';
    }
  }

  /// イヤホン・物理ボタンの入力を現在のモードに応じて処理する。ワークアウト完了時は true を返す。
  bool handleButtonAction(ButtonAction action) {
    if (_exercises.isEmpty) return false;

    // 前の曲ボタンは全モード共通で種目内容の読み上げ確認のみ行う
    if (action == ButtonAction.mediaPrevious) {
      onConfirmCurrentStatus();
      return false;
    }

    switch (_mode) {
      case TrainingMode.normal:
        return _handleNormalModeButton(action);
      case TrainingMode.adjustSelect:
        _handleAdjustSelectModeButton(action);
        return false;
      case TrainingMode.adjustValue:
        _handleAdjustValueModeButton(action);
        return false;
    }
  }

  bool _handleNormalModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        return advanceOrComplete();
      case ButtonAction.mediaNext:
        enterAdjustSelectMode();
        return false;
      case ButtonAction.mediaPrevious:
        onConfirmCurrentStatus();
        return false;
      case ButtonAction.volumeUp:
      case ButtonAction.volumeDown:
        // 通常モード時は誤操作防止のため無効
        return false;
    }
  }

  void _handleAdjustSelectModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.volumeUp:
        cycleAdjustmentTarget(step: 1);
        break;
      case ButtonAction.volumeDown:
        cycleAdjustmentTarget(step: -1);
        break;
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        enterAdjustValueMode();
        break;
      case ButtonAction.mediaNext:
        finishAdjustmentAndStart();
        break;
      case ButtonAction.mediaPrevious:
        onConfirmCurrentStatus();
        break;
    }
  }

  void _handleAdjustValueModeButton(ButtonAction action) {
    switch (action) {
      case ButtonAction.volumeUp:
        adjustCurrentTargetValue(increase: true);
        break;
      case ButtonAction.volumeDown:
        adjustCurrentTargetValue(increase: false);
        break;
      case ButtonAction.mediaPlayPause:
      case ButtonAction.headsetHook:
        confirmAdjustValue();
        break;
      case ButtonAction.mediaNext:
        finishAdjustmentAndStart();
        break;
      case ButtonAction.mediaPrevious:
        onConfirmCurrentStatus();
        break;
    }
  }

  /// 現在の種目・重量・回数・セット数を音声で確認する
  void onConfirmCurrentStatus() {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    _speak(currentSummarySpeech);
  }

  /// 通常モードから調整モード・階層1（項目選択）へ移行する
  void enterAdjustSelectMode({AdjustmentTarget? initialTarget}) {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    _mode = TrainingMode.adjustSelect;
    _selectedTarget = initialTarget ?? AdjustmentTarget.exercise;
    _candidateExerciseIndex = _currentIndex;
    notifyListeners();
    _speak('調整、${_selectedTarget.label}');
  }

  /// 調整モード・階層1で対象項目を循環移動する
  void cycleAdjustmentTarget({int step = 1}) {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    _playBeep();

    const targets = AdjustmentTarget.values;
    final currentIdx = targets.indexOf(_selectedTarget);
    final nextIdx = (currentIdx + step) % targets.length;
    _selectedTarget =
        targets[nextIdx < 0 ? nextIdx + targets.length : nextIdx];

    notifyListeners();
    _speak(_selectedTarget.label);
  }

  /// 調整モード・階層1から階層2（値の調整）へ移行する
  void enterAdjustValueMode() {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    _candidateExerciseIndex = _currentIndex;
    _mode = TrainingMode.adjustValue;
    _playBeep();
    notifyListeners();
    _speak(speechForTargetValue(_selectedTarget));
  }

  /// 調整モード・階層2で選択中項目の値を増減する
  void adjustCurrentTargetValue({required bool increase}) {
    if (_exercises.isEmpty) return;
    switch (_selectedTarget) {
      case AdjustmentTarget.exercise:
        _playBeep();
        final step = increase ? 1 : -1;
        final next = (_candidateExerciseIndex + step) % _exercises.length;
        _candidateExerciseIndex =
            next < 0 ? next + _exercises.length : next;
        notifyListeners();
        _scheduleDebouncedSpeech(
          () => speechForTargetValue(AdjustmentTarget.exercise),
        );
        break;
      case AdjustmentTarget.weight:
        adjustWeight(increase ? weightStepKg : -weightStepKg);
        break;
      case AdjustmentTarget.reps:
        adjustReps(increase ? 1 : -1);
        break;
      case AdjustmentTarget.sets:
        adjustSets(increase ? 1 : -1);
        break;
    }
  }

  /// 調整モード・階層2で変更を確定し、階層1（項目選択）へ戻る
  void confirmAdjustValue() {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    _commitCandidateExerciseSwapIfNeeded();
    _mode = TrainingMode.adjustSelect;
    _playBeep();
    notifyListeners();
    _speak('調整、${_selectedTarget.label}');
  }

  /// 調整モードを終了し、変更内容を確定して通常モードへ一発復帰する
  void finishAdjustmentAndStart() {
    if (_exercises.isEmpty) return;
    _cancelDebounce();
    if (_mode == TrainingMode.adjustValue) {
      _commitCandidateExerciseSwapIfNeeded();
    }
    _mode = TrainingMode.normal;
    _isStarted = true;
    notifyListeners();
    _speak('確定、開始、$currentSummarySpeech');
  }

  void _commitCandidateExerciseSwapIfNeeded() {
    if (_selectedTarget == AdjustmentTarget.exercise &&
        _candidateExerciseIndex != _currentIndex &&
        _candidateExerciseIndex >= 0 &&
        _candidateExerciseIndex < _exercises.length) {
      final temp = _exercises[_currentIndex];
      _exercises[_currentIndex] = _exercises[_candidateExerciseIndex];
      _exercises[_candidateExerciseIndex] = temp;
      _candidateExerciseIndex = _currentIndex;
    }
  }

  /// 現在表示中の種目（_currentIndex）と [newIndex] の種目の順番をその場で入れ替える
  void swapExercise(int newIndex) {
    if (_exercises.isEmpty ||
        newIndex < 0 ||
        newIndex >= _exercises.length ||
        newIndex == _currentIndex) {
      return;
    }
    _cancelDebounce();
    _playBeep();
    final temp = _exercises[_currentIndex];
    _exercises[_currentIndex] = _exercises[newIndex];
    _exercises[newIndex] = temp;
    _candidateExerciseIndex = _currentIndex;
    notifyListeners();
    _speak(currentExercise.machine.name);
  }

  /// noukin_app 互換エイリアス
  void swapExerciseWith(int targetIndex) => swapExercise(targetIndex);

  /// 現在の種目の重量を [delta] kg 調整する（最小 2.5 kg）
  void adjustWeight(double delta) {
    if (_exercises.isEmpty || !delta.isFinite || delta == 0) return;
    final targetIndex = _activeAdjustmentIndex;
    final current = _exercises[targetIndex];
    final baseWeight = (current.weightKg.isFinite && current.weightKg > 0.0)
        ? current.weightKg
        : minWeightKg;
    final raw = baseWeight + delta;
    if (!raw.isFinite) return;
    final rounded = double.parse(raw.toStringAsFixed(1));
    final clamped = math.max(minWeightKg, rounded);
    _playBeep();
    _exercises[targetIndex] = current.copyWith(weightKg: clamped);
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.weight),
    );
  }

  /// 現在の種目のレップ数を [delta] 回調整する（最小 1 回）
  void adjustReps(int delta) {
    if (_exercises.isEmpty || delta == 0) return;
    final targetIndex = _activeAdjustmentIndex;
    final current = _exercises[targetIndex];
    final clamped = math.max(minReps, current.reps + delta);
    _playBeep();
    _exercises[targetIndex] = current.copyWith(reps: clamped);
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.reps),
    );
  }

  /// 現在の種目のセット数を [delta] セット調整する（最小 1 セット）
  void adjustSets(int delta) {
    if (_exercises.isEmpty || delta == 0) return;
    final targetIndex = _activeAdjustmentIndex;
    final current = _exercises[targetIndex];
    final clamped = math.max(minSets, current.sets + delta);
    _playBeep();
    _exercises[targetIndex] = current.copyWith(sets: clamped);
    notifyListeners();
    _scheduleDebouncedSpeech(
      () => speechForTargetValue(AdjustmentTarget.sets),
    );
  }

  /// 「開始 / 次へ」ボタン押下時の進行処理。最終種目の完了時は true を返す。
  bool advanceOrComplete() {
    if (_exercises.isEmpty) return false;
    _cancelDebounce();
    if (_mode == TrainingMode.adjustValue) {
      _commitCandidateExerciseSwapIfNeeded();
    }
    _mode = TrainingMode.normal;

    if (!_isStarted) {
      _isStarted = true;
      notifyListeners();
      _speak('開始、$currentSummarySpeech');
      return false;
    }
    if (_currentIndex < _exercises.length - 1) {
      _currentIndex++;
      _candidateExerciseIndex = _currentIndex;
      notifyListeners();
      _speak('次へ、$currentSummarySpeech');
      return false;
    }
    notifyListeners();
    _speak('完了、お疲れ様でした');
    onWorkoutCompleted?.call();
    return true;
  }

  /// 編集・入れ替え後の種目リストをそのまま返す（advanceSessionDay への入力用）
  List<PrescribedExercise> get updatedPrescribedExercises =>
      List<PrescribedExercise>.unmodifiable(_exercises);

  /// 編集・入れ替え後の種目リストを履歴保存用レコードへ変換する
  List<CompletedExerciseRecord> toCompletedRecords() {
    return _exercises
        .map(
          (exercise) =>
              CompletedExerciseRecord.fromPrescribed(exercise, completed: true),
        )
        .toList(growable: false);
  }

  void _scheduleDebouncedSpeech(String Function() speechBuilder) {
    _cancelDebounce();
    if (ttsService == null) return;
    _debounceTimer = Timer(kDebounceDuration, () {
      _framePumpTimer?.cancel();
      _framePumpTimer = null;
      _debounceTimer = null;
      _speak(speechBuilder());
    });

    // ウィジェットテストの pumpAndSettle() 実行時にデバウンス完了までフレームを進行させる
    _framePumpTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_debounceTimer == null || !_debounceTimer!.isActive) {
        timer.cancel();
        return;
      }
      try {
        SchedulerBinding.instance.scheduleFrame();
      } catch (_) {}
    });
    try {
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _framePumpTimer?.cancel();
    _framePumpTimer = null;
  }

  void _playBeep() {
    final service = soundEffectService;
    if (service != null) {
      unawaited(service.playBeep());
    }
  }

  void _speak(String text) {
    if (text.isEmpty) return;
    final service = ttsService;
    if (service != null) {
      unawaited(service.speak(text));
    }
  }

  @override
  void dispose() {
    _cancelDebounce();
    final service = ttsService;
    if (service != null) {
      unawaited(service.stop());
    }
    super.dispose();
  }
}
