import 'package:flutter/material.dart';

import '../engine/workout_menu_generator.dart';
import '../theme/app_colors.dart';

/// 筋肉の優先度4段階（内部 P 値 0 / 10 / 14 / 18 に対応）
enum PriorityTier {
  untargeted(value: 0, label: '対象外'),
  standard(value: 10, label: '標準'),
  priority(value: 14, label: '優先'),
  highest(value: 18, label: '最優先');

  final int value;
  final String label;

  const PriorityTier({required this.value, required this.label});

  /// 内部の優先度数値 P_i を正規化して4段階ティアへ変換する
  static PriorityTier fromPriorityP(int priorityP) {
    final normalized = WorkoutMenuGenerator.normalizePriorityTierVal(priorityP);
    return switch (normalized) {
      0 => PriorityTier.untargeted,
      14 => PriorityTier.priority,
      18 => PriorityTier.highest,
      _ => PriorityTier.standard,
    };
  }

  /// 複数筋肉の優先度平均値に最も近い代表ティアを算出する
  static PriorityTier fromAverage(double averageP) {
    var best = PriorityTier.standard;
    var bestDiff = double.infinity;
    for (final tier in PriorityTier.values) {
      final diff = (averageP - tier.value).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = tier;
      }
    }
    return best;
  }

  PriorityTier? get previous =>
      index > 0 ? PriorityTier.values[index - 1] : null;

  PriorityTier? get next =>
      index < PriorityTier.values.length - 1
          ? PriorityTier.values[index + 1]
          : null;
}

/// 4段階優先度セレクター（< / ラベル＋4本インジケーター / >）
class PriorityTierSelector extends StatelessWidget {
  final PriorityTier tier;
  final ValueChanged<PriorityTier> onChanged;
  final Key? decrementButtonKey;
  final Key? incrementButtonKey;

  const PriorityTierSelector({
    super.key,
    required this.tier,
    required this.onChanged,
    this.decrementButtonKey,
    this.incrementButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    final prev = tier.previous;
    final next = tier.next;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildArrowButton(
          key: decrementButtonKey,
          icon: Icons.chevron_left,
          tooltip: '優先度を下げる',
          onTap: prev != null ? () => onChanged(prev) : null,
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 74,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tier.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: tier == PriorityTier.untargeted
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 0; i < PriorityTier.values.length; i++) ...[
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i == tier.index
                              ? AppColors.tealAccent
                              : AppColors.trackInactive,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (i < PriorityTier.values.length - 1)
                      const SizedBox(width: 4),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _buildArrowButton(
          key: incrementButtonKey,
          icon: Icons.chevron_right,
          tooltip: '優先度を上げる',
          onTap: next != null ? () => onChanged(next) : null,
        ),
      ],
    );
  }

  Widget _buildArrowButton({
    required Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return IconButton(
      key: key,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: enabled
            ? AppColors.background
            : AppColors.background.withValues(alpha: 0.45),
        foregroundColor: enabled
            ? AppColors.tealAccent
            : AppColors.textTertiary,
        disabledForegroundColor: AppColors.textTertiary,
        disabledBackgroundColor: AppColors.background.withValues(alpha: 0.45),
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: enabled ? AppColors.border : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
