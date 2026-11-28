import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/controllers/training_session_controller.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/screens/review_screen.dart';
import 'package:noukin/screens/training_flow_screen.dart';
import 'package:noukin/screens/training_screen.dart';
import 'package:noukin/services/earphone_audio_service.dart';
import 'package:noukin/theme/app_colors.dart';
import 'package:noukin/theme/app_theme.dart';

void main() {
  const defaultProfile = UserProfile(
    id: 'test-earphone',
    gender: Gender.male,
    birthYear: 1995,
    experience: ExperienceLevel.beginner,
    bodyWeightKg: 70.0,
    purpose: TrainingPurpose.bodyMakeMale,
    isFirstTime: true,
  );

  List<PrescribedExercise> sampleExercises() => <PrescribedExercise>[
    PrescribedExercise(
      machine: MasterData.machines[0],
      weightKg: 60.0,
      reps: 10,
      sets: 3,
      primaryMuscleNames: const <String>['大腿四頭筋'],
      synergistMuscleNames: const <String>['大臀筋'],
    ),
    PrescribedExercise(
      machine: MasterData.machines[10],
      weightKg: 40.0,
      reps: 12,
      sets: 3,
      primaryMuscleNames: const <String>['大胸筋'],
      synergistMuscleNames: const <String>['上腕三頭筋'],
    ),
    PrescribedExercise(
      machine: MasterData.machines[15],
      weightKg: 50.0,
      reps: 8,
      sets: 4,
      primaryMuscleNames: const <String>['広背筋'],
      synergistMuscleNames: const <String>['上腕二頭筋'],
    ),
  ];

  group('1. ButtonAction & KeyEventChannelDispatcher', () {
    test('fromKeyCode maps all 6 target keycodes and rejects others', () {
      expect(ButtonAction.fromKeyCode(24), ButtonAction.volumeUp);
      expect(ButtonAction.fromKeyCode(25), ButtonAction.volumeDown);
      expect(ButtonAction.fromKeyCode(85), ButtonAction.mediaPlayPause);
      expect(ButtonAction.fromKeyCode(79), ButtonAction.headsetHook);
      expect(ButtonAction.fromKeyCode(87), ButtonAction.mediaNext);
      expect(ButtonAction.fromKeyCode(88), ButtonAction.mediaPrevious);
      expect(ButtonAction.fromKeyCode(999), isNull);
    });

    testWidgets(
      'KeyEventChannelDispatcher toggles Android key interception on register/unregister and routes onKeyEvent',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final channelCalls = <MethodCall>[];
        const channel = MethodChannel(kKeyEventsChannelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              channelCalls.add(call);
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final received = <ButtonAction>[];
        void listener(ButtonAction action) => received.add(action);

        KeyEventChannelDispatcher.instance.registerListener(listener);
        await tester.pump();

        expect(
          channelCalls.any(
            (c) =>
                c.method == 'setKeyInterceptionEnabled' && c.arguments == true,
          ),
          isTrue,
        );

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              kKeyEventsChannelName,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('onKeyEvent', 87),
              ),
              (_) {},
            );
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              kKeyEventsChannelName,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('onKeyEvent', 79),
              ),
              (_) {},
            );
        expect(received, <ButtonAction>[
          ButtonAction.mediaNext,
          ButtonAction.headsetHook,
        ]);

        channelCalls.clear();
        KeyEventChannelDispatcher.instance.unregisterListener(listener);
        await tester.pump();
        expect(
          channelCalls.any(
            (c) =>
                c.method == 'setKeyInterceptionEnabled' && c.arguments == false,
          ),
          isTrue,
        );
      },
    );
  });

  group('2. TrainingSessionController 3-mode earphone state machine & TTS/beep', () {
    test(
      'normal -> adjustSelect -> adjustValue -> normal cycle with debounced TTS & candidate swap',
      () async {
        final tts = FakeTtsService();
        final sfx = FakeSoundEffectService();
        final exercises = sampleExercises();
        var completedCount = 0;

        final controller = TrainingSessionController.fromExercises(
          exercises: exercises,
          ttsService: tts,
          soundEffectService: sfx,
          onWorkoutCompleted: () => completedCount++,
        );
        addTearDown(controller.dispose);

        // Normal mode: volume keys are ignored (no beep, no TTS, no change)
        expect(controller.mode, TrainingMode.normal);
        expect(controller.handleButtonAction(ButtonAction.volumeUp), isFalse);
        expect(controller.handleButtonAction(ButtonAction.volumeDown), isFalse);
        expect(sfx.beepCount, 0);
        expect(tts.spokenHistory, isEmpty);

        // Normal mode: mediaPrevious announces current summary without changing state
        controller.handleButtonAction(ButtonAction.mediaPrevious);
        expect(controller.mode, TrainingMode.normal);
        expect(controller.isStarted, isFalse);
        expect(
          tts.lastSpoken,
          '${exercises[0].machine.name}、60kg、10回、3セット',
        );

        // Normal mode: mediaNext enters adjustSelect (default target: exercise)
        controller.handleButtonAction(ButtonAction.mediaNext);
        expect(controller.mode, TrainingMode.adjustSelect);
        expect(controller.selectedTarget, AdjustmentTarget.exercise);
        expect(tts.lastSpoken, '調整、種目名');

        // Cycle targets with volumeUp / volumeDown
        controller.handleButtonAction(ButtonAction.volumeUp);
        expect(controller.selectedTarget, AdjustmentTarget.weight);
        expect(sfx.beepCount, 1);
        expect(tts.lastSpoken, '重量');

        controller.handleButtonAction(ButtonAction.volumeUp);
        expect(controller.selectedTarget, AdjustmentTarget.reps);
        expect(tts.lastSpoken, 'レップ数');

        controller.handleButtonAction(ButtonAction.volumeDown);
        expect(controller.selectedTarget, AdjustmentTarget.weight);
        expect(tts.lastSpoken, '重量');

        // Enter adjustValue for weight
        controller.handleButtonAction(ButtonAction.mediaPlayPause);
        expect(controller.mode, TrainingMode.adjustValue);
        expect(tts.lastSpoken, '60kg');

        // Adjust weight twice quickly -> immediate beep, debounced TTS after 700ms
        final spokenBeforeAdjust = tts.speakCount;
        controller.handleButtonAction(ButtonAction.volumeUp);
        controller.handleButtonAction(ButtonAction.volumeUp);
        expect(controller.weightKg, 65.0);
        expect(tts.speakCount, spokenBeforeAdjust);

        await Future<void>.delayed(const Duration(milliseconds: 780));
        expect(tts.lastSpoken, '65kg');

        // Confirm value -> returns to adjustSelect
        controller.handleButtonAction(ButtonAction.mediaPlayPause);
        expect(controller.mode, TrainingMode.adjustSelect);
        expect(tts.lastSpoken, '調整、重量');

        // Cycle back to exercise, enter adjustValue, preview index 1, then finish with mediaNext
        controller.handleButtonAction(ButtonAction.volumeDown);
        expect(controller.selectedTarget, AdjustmentTarget.exercise);
        controller.handleButtonAction(ButtonAction.headsetHook);
        expect(controller.mode, TrainingMode.adjustValue);
        expect(tts.lastSpoken, exercises[0].machine.name);

        controller.handleButtonAction(ButtonAction.volumeUp);
        expect(
          controller.displayedExerciseOrNull?.machine.id,
          exercises[1].machine.id,
        );
        await Future<void>.delayed(const Duration(milliseconds: 780));
        expect(tts.lastSpoken, exercises[1].machine.name);

        // mediaNext commits candidate swap and resumes normal started state
        controller.handleButtonAction(ButtonAction.mediaNext);
        expect(controller.mode, TrainingMode.normal);
        expect(controller.isStarted, isTrue);
        expect(controller.currentExercise.machine.id, exercises[1].machine.id);
        expect(controller.exercises[1].machine.id, exercises[0].machine.id);
        expect(
          tts.lastSpoken,
          '確定、開始、${exercises[1].machine.name}、40kg、12回、3セット',
        );

        // Advance through remaining exercises until completion
        expect(
          controller.handleButtonAction(ButtonAction.mediaPlayPause),
          isFalse,
        );
        expect(controller.currentIndex, 1);
        expect(tts.lastSpoken, '次へ、${exercises[0].machine.name}、65kg、10回、3セット');

        expect(
          controller.handleButtonAction(ButtonAction.headsetHook),
          isFalse,
        );
        expect(controller.currentIndex, 2);

        expect(
          controller.handleButtonAction(ButtonAction.mediaPlayPause),
          isTrue,
        );
        expect(completedCount, 1);
        expect(tts.lastSpoken, '完了、お疲れ様でした');
      },
    );

    test(
      'screen tap actions also emit beep and debounced/immediate TTS',
      () async {
        final tts = FakeTtsService();
        final sfx = FakeSoundEffectService();
        final exercises = sampleExercises();

        final controller = TrainingSessionController.fromExercises(
          exercises: exercises,
          ttsService: tts,
          soundEffectService: sfx,
        );
        addTearDown(controller.dispose);

        expect(controller.advanceOrComplete(), isFalse);
        expect(tts.lastSpoken, '開始、${exercises[0].machine.name}、60kg、10回、3セット');

        controller.adjustWeight(2.5);
        expect(sfx.beepCount, 1);
        await Future<void>.delayed(const Duration(milliseconds: 780));
        expect(tts.lastSpoken, '62.5kg');

        controller.adjustReps(1);
        expect(sfx.beepCount, 2);
        await Future<void>.delayed(const Duration(milliseconds: 780));
        expect(tts.lastSpoken, '11回');

        controller.adjustSets(-1);
        expect(sfx.beepCount, 3);
        await Future<void>.delayed(const Duration(milliseconds: 780));
        expect(tts.lastSpoken, '2セット');

        controller.swapExercise(2);
        expect(sfx.beepCount, 4);
        expect(tts.lastSpoken, exercises[2].machine.name);
      },
    );
  });

  group('3. TrainingScreen UI highlights, keyboard shortcuts & Android lifecycle', () {
    testWidgets(
      'highlights cards in adjustSelect/adjustValue without showing volume slider or media bar',
      (WidgetTester tester) async {
        final tts = FakeTtsService();
        final sfx = FakeSoundEffectService();
        final controller = TrainingSessionController.fromExercises(
          exercises: sampleExercises(),
          ttsService: tts,
          soundEffectService: sfx,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: TrainingScreen(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // UI remains free of slider and media bar
        expect(find.byType(Slider), findsNothing);
        expect(find.byKey(const Key('card_volume')), findsNothing);
        expect(find.byKey(const Key('media_control_bar')), findsNothing);

        // Press ArrowRight -> adjustSelect (exercise)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(controller.mode, TrainingMode.adjustSelect);
        expect(controller.selectedTarget, AdjustmentTarget.exercise);

        // Press ArrowUp -> adjustSelect (weight) -> card_weight highlighted in teal
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(controller.selectedTarget, AdjustmentTarget.weight);
        var weightCard = tester.widget<Card>(
          find.byKey(const Key('card_weight')),
        );
        expect(weightCard.color, AppColors.highlightSelectedSurface);

        // Press Space -> adjustValue (weight) -> card_weight highlighted in editing orange surface
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(controller.mode, TrainingMode.adjustValue);
        weightCard = tester.widget<Card>(find.byKey(const Key('card_weight')));
        expect(weightCard.color, AppColors.highlightEditingSurface);

        // Press ArrowUp -> increments weight and speaks after 700ms
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 800));
        expect(controller.weightKg, 62.5);
        expect(tts.lastSpoken, '62.5kg');

        // Press ArrowLeft -> reads summary safely
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(tts.lastSpoken, contains('62.5kg'));
      },
    );

    testWidgets(
      'TrainingFlowScreen disables Android key interception on ReviewScreen and keeps it disabled on A1',
      (WidgetTester tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final interceptionLog = <bool>[];
        const channel = MethodChannel(kKeyEventsChannelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'setKeyInterceptionEnabled') {
                interceptionLog.add(call.arguments as bool);
                return true;
              }
              if (call.method == 'playBeep') {
                return true;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final tts = FakeTtsService();
        final sfx = FakeSoundEffectService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: TrainingFlowScreen(
              profile: defaultProfile,
              muscleStates: MasterData.defaultMuscleStates(
                defaultProfile.purpose,
              ),
              machineHistory: MasterData.defaultMachineHistory(),
              clock: () => DateTime(2026, 11, 20, 18, 0),
              ttsService: tts,
              soundEffectService: sfx,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Screen A1: interception has not been enabled
        expect(interceptionLog, isEmpty);

        // Select 20-min course (2 exercises) and start
        await tester.tap(find.byKey(const Key('course_short')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_start_workout')));
        await tester.pumpAndSettle();

        expect(find.byType(TrainingScreen), findsOneWidget);
        expect(interceptionLog.last, isTrue);

        // Complete workout via earphone mediaPlayPause (start -> next -> complete)
        for (var i = 0; i < 3; i++) {
          await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                kKeyEventsChannelName,
                const StandardMethodCodec().encodeMethodCall(
                  const MethodCall('onKeyEvent', 85),
                ),
                (_) {},
              );
          await tester.pumpAndSettle();
        }

        // Now on ReviewScreen: interception must be disabled
        expect(find.byType(ReviewScreen), findsOneWidget);
        expect(interceptionLog.last, isFalse);

        // Finish ReviewScreen -> back on A1
        await tester.tap(find.byKey(const Key('feedback_just_right')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_finish_workout')));
        await tester.pumpAndSettle();

        expect(find.byType(ReviewScreen), findsNothing);
        expect(interceptionLog.last, isFalse);
      },
    );
  });
}
