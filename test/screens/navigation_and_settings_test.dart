import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noukin/app.dart';
import 'package:noukin/data/master_data.dart';
import 'package:noukin/models/models.dart';
import 'package:noukin/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('M5 Navigation, Screen B, Screen C & AppState Integration', () {
    testWidgets(
      '3-tab navigation switches cleanly between Screen A, Screen B, and Screen C',
      (WidgetTester tester) async {
        final fixedNow = DateTime(2026, 11, 20, 9, 0);
        await tester.pumpWidget(NoukinApp(clock: () => fixedNow));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
        expect(find.byKey(const Key('detected_timeslot_badge')), findsOneWidget);

        // Navigate to Screen B (new 3-screen main view)
        await tester.tap(find.byKey(const Key('nav_tab_custom')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('purpose_selector')), findsOneWidget);
        expect(find.byKey(const Key('btn_sub_controls')), findsOneWidget);
        expect(find.byKey(const Key('muscle_matrix_list')), findsOneWidget);
        // Sub-screens are not rendered inline on the main custom screen
        expect(find.byKey(const Key('injury_filter_section')), findsNothing);
        expect(find.byKey(const Key('group_batch_section')), findsNothing);

        // Navigate to Screen C
        await tester.tap(find.byKey(const Key('nav_tab_settings')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_select_machines')), findsOneWidget);
        expect(find.byKey(const Key('gender_selector')), findsOneWidget);
        expect(find.byKey(const Key('birth_year_input')), findsOneWidget);
        expect(find.byKey(const Key('experience_selector')), findsOneWidget);
        expect(find.byKey(const Key('body_weight_input')), findsOneWidget);
        expect(find.byKey(const Key('btn_save_profile')), findsOneWidget);
        expect(find.byKey(const Key('btn_google_login')), findsOneWidget);

        // Return to Screen A
        await tester.tap(find.byKey(const Key('nav_tab_training')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_start_workout')), findsOneWidget);
      },
    );

    testWidgets(
      'Custom Settings 3-screen flow: priority tiers (0/10/14/18), group batch, and injury filter',
      (WidgetTester tester) async {
        final appState = AppState(clock: () => DateTime(2026, 11, 20, 12, 0));
        await appState.initialize();

        await tester.pumpWidget(NoukinApp(appState: appState));
        await tester.pumpAndSettle();

        // Open Screen B
        await tester.tap(find.byKey(const Key('nav_tab_custom')));
        await tester.pumpAndSettle();

        // Main card shows muscle name (group), blank days, and 4-tier selector only
        final rowM0 = find.byKey(const Key('matrix_row_m0'));
        expect(rowM0, findsOneWidget);
        expect(
          find.descendant(of: rowM0, matching: find.text('大腿四頭筋（脚・臀部）')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rowM0, matching: find.text('ブランク: 4日')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rowM0, matching: find.text('最優先')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rowM0, matching: find.textContaining('M:')),
          findsNothing,
        );
        expect(
          find.descendant(of: rowM0, matching: find.textContaining('S:')),
          findsNothing,
        );

        // Step down m0 priority across all 4 tiers: 18 -> 14 -> 10 -> 0
        await tester.tap(find.byKey(const Key('priority_dec_m0')));
        await tester.pumpAndSettle();
        expect(appState.muscleStates['m0']!.priorityP, 14);
        expect(
          find.descendant(of: rowM0, matching: find.text('優先')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('priority_dec_m0')));
        await tester.pumpAndSettle();
        expect(appState.muscleStates['m0']!.priorityP, 10);
        expect(
          find.descendant(of: rowM0, matching: find.text('標準')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('priority_dec_m0')));
        await tester.pumpAndSettle();
        expect(appState.muscleStates['m0']!.priorityP, 0);
        expect(
          find.descendant(of: rowM0, matching: find.text('対象外')),
          findsOneWidget,
        );
        expect(appState.computeCurrentMuscleScores()['m0']!.mVal, 0.0);

        // Open Sub Controls -> Group Batch Adjustment Screen
        await tester.tap(find.byKey(const Key('btn_sub_controls')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('sub_control_group_batch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('sub_control_injury_filter')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('sub_control_group_batch')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('group_batch_section')), findsOneWidget);
        for (final group in MuscleGroup.values) {
          expect(
            find.byKey(Key('group_batch_${group.name}')),
            findsOneWidget,
          );
        }

        // Batch adjust chest group priority up or down
        final chestMuscles = MasterData.muscles
            .where((m) => m.group == MuscleGroup.chest)
            .map((m) => m.id)
            .toList();
        await tester.tap(find.byKey(const Key('group_batch_inc_chest')));
        await tester.pumpAndSettle();
        final expectedChestP = appState.muscleStates[chestMuscles.first]!.priorityP;
        expect([10, 14, 18], contains(expectedChestP));
        for (final id in chestMuscles) {
          expect(appState.muscleStates[id]!.priorityP, expectedChestP);
        }

        // Return to Custom main screen
        await tester.tap(find.byKey(const Key('btn_back_group_batch')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_sub_controls')), findsOneWidget);

        // Open Sub Controls -> Injury Filter Screen
        await tester.tap(find.byKey(const Key('btn_sub_controls')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('sub_control_injury_filter')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('injury_filter_section')), findsOneWidget);

        final m0Chip = find.byKey(const Key('injury_toggle_m0'));
        // Unselected chip has no warning icon
        expect(
          find.descendant(
            of: m0Chip,
            matching: find.byIcon(Icons.warning_amber_rounded),
          ),
          findsNothing,
        );

        // Select m0 as injured -> warning icon appears and M = 0
        await tester.tap(m0Chip);
        await tester.pumpAndSettle();
        expect(appState.muscleStates['m0']!.isInjured, isTrue);
        expect(
          find.descendant(
            of: m0Chip,
            matching: find.byIcon(Icons.warning_amber_rounded),
          ),
          findsOneWidget,
        );
        expect(appState.computeCurrentMuscleScores()['m0']!.mVal, 0.0);
        expect(
          appState.computeCurrentMuscleScores()['m0']!.status,
          MuscleScoreStatus.injured,
        );

        // Return to Custom main screen
        await tester.tap(find.byKey(const Key('btn_back_injury_filter')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_sub_controls')), findsOneWidget);
      },
    );

    testWidgets(
      'Screen C Machine Selection: navigates from profile top button, enforces minimum 1 machine, and filters generated menu',
      (WidgetTester tester) async {
        final appState = AppState(clock: () => DateTime(2026, 11, 25, 10, 0));
        await appState.initialize();

        await tester.pumpWidget(NoukinApp(appState: appState));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nav_tab_settings')));
        await tester.pumpAndSettle();

        final selectMachinesBtn = find.byKey(const Key('btn_select_machines'));
        expect(selectMachinesBtn, findsOneWidget);
        expect(
          find.descendant(
            of: selectMachinesBtn,
            matching: find.text('29 / 29 台'),
          ),
          findsOneWidget,
        );

        await tester.tap(selectMachinesBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('machine_selection_list')), findsOneWidget);
        expect(find.byKey(const Key('btn_search_gym')), findsOneWidget);
        expect(find.byKey(const Key('btn_save_machines')), findsOneWidget);
        expect(find.byKey(const Key('btn_select_all_machines')), findsNothing);
        expect(find.textContaining('利用可能なマシン'), findsNothing);
        for (final group in MuscleGroup.values) {
          expect(
            find.byKey(Key('machine_group_${group.name}')),
            findsOneWidget,
          );
        }

        // Disable all groups except chest so only chest machines remain
        for (final group in MuscleGroup.values) {
          if (group == MuscleGroup.chest) continue;
          final toggleBtn = find.byKey(
            Key('machine_group_toggle_${group.name}'),
          );
          await tester.ensureVisible(toggleBtn);
          await tester.tap(toggleBtn);
          await tester.pumpAndSettle();
        }

        // Disable all chest machines except mac11 (keep 1 machine)
        final chestMachines = MasterData.machines
            .where((m) => m.category == MuscleGroup.chest)
            .toList();
        for (final mac in chestMachines) {
          if (mac.id == 'mac11') continue;
          final card = find.byKey(Key('machine_toggle_${mac.id}'));
          await tester.ensureVisible(card);
          await tester.tap(card);
          await tester.pumpAndSettle();
        }

        // Trying to disable the last remaining machine must be rejected
        final lastCard = find.byKey(const Key('machine_toggle_mac11'));
        await tester.ensureVisible(lastCard);
        await tester.tap(lastCard);
        await tester.pumpAndSettle();
        expect(find.text('最低1台以上のマシンを選択してください'), findsOneWidget);

        // Draft mode: AppState is not mutated until Save is pressed
        expect(appState.availableMachineIds.length, 29);

        // Tap Save button to persist draft and pop back to Screen C
        await tester.tap(find.byKey(const Key('btn_save_machines')));
        await tester.pumpAndSettle();
        expect(appState.availableMachineIds, equals(const <String>{'mac11'}));
        expect(
          find.descendant(
            of: find.byKey(const Key('btn_select_machines')),
            matching: find.text('1 / 29 台'),
          ),
          findsOneWidget,
        );

        // Start workout on Screen A and verify only mac11 is prescribed
        await tester.tap(find.byKey(const Key('nav_tab_training')));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final startBtn = find.byKey(const Key('btn_start_workout'));
        await tester.ensureVisible(startBtn);
        await tester.tap(startBtn);
        await tester.pumpAndSettle();
        expect(
          appState.lastMenuResult!.exercises.map((e) => e.machine.id).toList(),
          equals(const <String>['mac11']),
        );
      },
    );

    testWidgets(
      'Gym search validates Japanese-only input, registers new gym, links machines, and updates gym master only via bottom button',
      (WidgetTester tester) async {
        final appState = AppState(clock: () => DateTime(2026, 11, 25, 11, 0));
        await appState.initialize();

        await tester.pumpWidget(NoukinApp(appState: appState));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nav_tab_settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_select_machines')));
        await tester.pumpAndSettle();

        // Open Gym Search sheet
        await tester.tap(find.byKey(const Key('btn_search_gym')));
        await tester.pumpAndSettle();

        // Non-Japanese input (alphanumeric) shows validation error and disables register/search
        await tester.enterText(
          find.byKey(const Key('gym_search_input')),
          'Anytime123',
        );
        await tester.pumpAndSettle();
        expect(find.text('カタカナ・ひらがな・漢字のみ入力できます'), findsOneWidget);
        expect(find.byKey(const Key('btn_register_gym')), findsNothing);

        // Valid Japanese input (カタカナ・ひらがな・漢字) enables search & register
        await tester.enterText(
          find.byKey(const Key('gym_search_input')),
          'エニタイム渋谷',
        );
        await tester.pumpAndSettle();
        expect(find.text('カタカナ・ひらがな・漢字のみ入力できます'), findsNothing);

        await tester.tap(find.byKey(const Key('btn_execute_gym_search')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('btn_register_gym')), findsOneWidget);

        // Register new gym
        await tester.tap(find.byKey(const Key('btn_register_gym')));
        await tester.pumpAndSettle();
        expect(find.text('選択中のジム: エニタイム渋谷'), findsOneWidget);

        // Personal toggle + Save does NOT overwrite gym master list
        final mac1Card = find.byKey(const Key('machine_toggle_mac1'));
        await tester.ensureVisible(mac1Card);
        await tester.tap(mac1Card);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_save_machines')));
        await tester.pumpAndSettle();

        expect(appState.availableMachineIds.contains('mac1'), isFalse);
        expect(appState.selectedGym!.machineIds.contains('mac1'), isTrue);

        // Re-open Machine Selection and use bottom button to update gym master list
        await tester.tap(find.byKey(const Key('btn_select_machines')));
        await tester.pumpAndSettle();

        final editGymBtn = find.byKey(const Key('btn_edit_gym_machines'));
        await tester.ensureVisible(editGymBtn);
        await tester.tap(editGymBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('gym_master_editing_banner')),
          findsOneWidget,
        );

        // Toggle mac1 off in gym master edit mode and trigger update
        await tester.ensureVisible(mac1Card);
        await tester.tap(mac1Card);
        await tester.pumpAndSettle();

        final updateGymBtn = find.byKey(const Key('btn_update_gym_machines'));
        await tester.ensureVisible(updateGymBtn);
        await tester.tap(updateGymBtn);
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(
          find.byKey(const Key('confirm_update_gym_dialog')),
          findsOneWidget,
        );
        expect(find.text('ジムの機材リストを更新しますか？'), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_confirm_update_gym')));
        await tester.pumpAndSettle();

        expect(appState.selectedGym!.machineIds.contains('mac1'), isFalse);
      },
    );

    test(
      'AppState enforces B_i (0..30), S_i (0.0..30.0), P_i (0..18), and profile validation bounds',
      () async {
        final appState = AppState(clock: () => DateTime(2026, 11, 20, 12, 0));
        await appState.initialize();

        await appState.updateMuscleState(
          'm0',
          blankDays: 99,
          stimulationDays: -5.0,
          priorityP: 40,
        );
        expect(appState.muscleStates['m0']!.blankDays, 30);
        expect(appState.muscleStates['m0']!.stimulationDays, 0.0);
        expect(appState.muscleStates['m0']!.priorityP, 18);

        await appState.updateMuscleState(
          'm0',
          blankDays: -10,
          stimulationDays: 99.9,
          priorityP: -3,
        );
        expect(appState.muscleStates['m0']!.blankDays, 0);
        expect(appState.muscleStates['m0']!.stimulationDays, 30.0);
        expect(appState.muscleStates['m0']!.priorityP, 0);

        // Invalid birthYear and bodyWeightKg are ignored, keeping previous valid values
        await appState.updateProfile(
          birthYear: 1850,
          bodyWeightKg: 5.0,
        );
        expect(appState.profile.birthYear, 1995);
        expect(appState.profile.bodyWeightKg, 65.0);

        // Valid update + gender auto-sync
        await appState.updateProfile(
          gender: Gender.female,
          birthYear: 1990,
          experience: ExperienceLevel.intermediate,
          bodyWeightKg: 54.0,
        );
        expect(appState.profile.gender, Gender.female);
        expect(appState.profile.purpose, TrainingPurpose.bodyMakeFemale);
        expect(appState.profile.birthYear, 1990);
        expect(appState.profile.experience, ExperienceLevel.intermediate);
        expect(appState.profile.bodyWeightKg, 54.0);
      },
    );
  });
}
