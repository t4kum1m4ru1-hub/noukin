import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../engine/workout_menu_generator.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/priority_tier_selector.dart';

/// サブコントロール遷移先①: 部位グループ別 一括調整画面（6大カテゴリ）
class GroupBatchAdjustmentScreen extends StatelessWidget {
  final AppState appState;

  const GroupBatchAdjustmentScreen({super.key, required this.appState});

  PriorityTier _resolveGroupRepresentativeTier(
    MuscleGroup group,
    Map<String, MuscleInputState> states,
  ) {
    final groupMuscles = MasterData.muscles
        .where((m) => m.group == group)
        .toList();
    if (groupMuscles.isEmpty) {
      return PriorityTier.standard;
    }

    var sum = 0;
    for (final muscle in groupMuscles) {
      final rawP = states[muscle.id]?.priorityP ?? 10;
      sum += WorkoutMenuGenerator.normalizePriorityTierVal(rawP);
    }
    return PriorityTier.fromAverage(sum / groupMuscles.length);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final states = appState.muscleStates;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              key: const Key('btn_back_group_batch'),
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              '部位グループ別 一括調整',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    key: const Key('group_batch_section'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final group in MuscleGroup.values) ...[
                        _buildGroupCard(
                          group: group,
                          representativeTier: _resolveGroupRepresentativeTier(
                            group,
                            states,
                          ),
                        ),
                        if (group != MuscleGroup.values.last)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupCard({
    required MuscleGroup group,
    required PriorityTier representativeTier,
  }) {
    return Container(
      key: Key('group_batch_${group.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              group.label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          PriorityTierSelector(
            tier: representativeTier,
            decrementButtonKey: Key('group_batch_dec_${group.name}'),
            incrementButtonKey: Key('group_batch_inc_${group.name}'),
            onChanged: (nextTier) {
              appState.applyGroupBatchAdjustment(
                group,
                prioritySet: nextTier.value,
              );
            },
          ),
        ],
      ),
    );
  }
}
