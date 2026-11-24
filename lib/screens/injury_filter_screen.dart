import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// サブコントロール遷移先②: ケガ部位フィルター画面
class InjuryFilterScreen extends StatelessWidget {
  final AppState appState;

  const InjuryFilterScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final states = appState.muscleStates;
        final injuredCount = states.values.where((s) => s.isInjured).length;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              key: const Key('btn_back_injury_filter'),
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'ケガ部位フィルター',
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
                  child: Container(
                    key: const Key('injury_filter_section'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.healing_outlined,
                              color: AppColors.tealAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ケガ部位フィルター（選択中: $injuredCount 部位）',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '選択された筋肉は M = 0 となり、対象マシンが候補から完全除外されます',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: MasterData.muscles.map((muscle) {
                            final isInjured =
                                states[muscle.id]?.isInjured ?? false;
                            return Material(
                              color: isInjured
                                  ? AppColors.error.withValues(alpha: 0.22)
                                  : AppColors.surfaceVariant,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isInjured
                                      ? AppColors.error
                                      : AppColors.border,
                                  width: isInjured ? 1.5 : 1.0,
                                ),
                              ),
                              child: InkWell(
                                key: Key('injury_toggle_${muscle.id}'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: () =>
                                    appState.toggleMuscleInjury(muscle.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isInjured) ...[
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 15,
                                          color: AppColors.error,
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Flexible(
                                        child: Text(
                                          muscle.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isInjured
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isInjured
                                                ? AppColors.error
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
