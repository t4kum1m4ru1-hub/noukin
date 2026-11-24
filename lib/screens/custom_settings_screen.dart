import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/priority_tier_selector.dart';
import 'group_batch_adjustment_screen.dart';
import 'injury_filter_screen.dart';

/// 画面 B: カスタム設定メイン画面（トレーニング目的・サブコントロール・全54筋肉の優先度設定）
class CustomSettingsScreen extends StatelessWidget {
  final AppState appState;

  const CustomSettingsScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final states = appState.muscleStates;
        final currentPurpose = appState.profile.purpose;
        final injuredCount = states.values.where((s) => s.isInjured).length;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'のう筋（Noukin） — カスタム設定',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              key: const Key('muscle_matrix_list'),
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPurposeSection(currentPurpose),
                      const SizedBox(height: 12),
                      _buildSubControlButton(context, injuredCount),
                      const SizedBox(height: 16),
                      for (final muscle in MasterData.muscles) ...[
                        _buildMuscleCard(
                          muscle: muscle,
                          state:
                              states[muscle.id] ??
                              MuscleInputState(
                                muscleId: muscle.id,
                                priorityP: 10,
                              ),
                        ),
                        if (muscle != MasterData.muscles.last)
                          const SizedBox(height: 8),
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

  Widget _buildPurposeSection(TrainingPurpose currentPurpose) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.flag_outlined, color: AppColors.tealAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'トレーニング目的',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TrainingPurpose>(
                key: const Key('purpose_selector'),
                value: currentPurpose,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                iconEnabledColor: AppColors.tealAccent,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                items: TrainingPurpose.values
                    .map(
                      (purpose) => DropdownMenuItem<TrainingPurpose>(
                        value: purpose,
                        child: Text(
                          purpose.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (newPurpose) {
                  if (newPurpose != null) {
                    appState.updatePurpose(newPurpose);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubControlButton(BuildContext context, int injuredCount) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        key: const Key('btn_sub_controls'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showSubControlSheet(context, injuredCount),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.tune, color: AppColors.tealAccent, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'サブコントロール',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (injuredCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(
                    'ケガ除外 $injuredCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSubControlSheet(
    BuildContext context,
    int injuredCount,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.trackInactive,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'サブコントロール',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSubControlOption(
                  key: const Key('sub_control_group_batch'),
                  icon: Icons.layers_outlined,
                  title: '部位グループ別 一括調整',
                  subtitle: '6大カテゴリ単位で優先度をまとめて変更',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            GroupBatchAdjustmentScreen(appState: appState),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildSubControlOption(
                  key: const Key('sub_control_injury_filter'),
                  icon: Icons.healing_outlined,
                  title: 'ケガ部位フィルター',
                  subtitle: injuredCount > 0
                      ? '選択中: $injuredCount 部位（M = 0 で除外）'
                      : 'ケガをしている筋肉をメニュー候補から完全除外',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InjuryFilterScreen(appState: appState),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubControlOption({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppColors.tealAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMuscleCard({
    required Muscle muscle,
    required MuscleInputState state,
  }) {
    final currentTier = PriorityTier.fromPriorityP(state.priorityP);

    return Container(
      key: Key('matrix_row_${muscle.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state.isInjured ? AppColors.error : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${muscle.name}（${muscle.group.label}）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ブランク: ${state.blankDays}日',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PriorityTierSelector(
            tier: currentTier,
            decrementButtonKey: Key('priority_dec_${muscle.id}'),
            incrementButtonKey: Key('priority_inc_${muscle.id}'),
            onChanged: (nextTier) {
              appState.updateMuscleState(
                muscle.id,
                priorityP: nextTier.value,
              );
            },
          ),
        ],
      ),
    );
  }
}
