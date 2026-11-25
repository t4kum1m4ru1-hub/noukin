import 'package:flutter/material.dart';

import '../data/master_data.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';

/// 設定画面から遷移する「マシンを選択」専用画面
/// - 上部: 「ジムを検索」ボタン（店舗検索・新規登録・店舗機材リスト反映）
/// - 右上: 「保存」ボタン（個人利用リストの確定保存）
/// - 最下部（店舗選択時）: 「店舗の機材リストを変更する」ボタン（共有リスト更新フロー）
class MachineSelectionScreen extends StatefulWidget {
  final AppState appState;

  const MachineSelectionScreen({super.key, required this.appState});

  @override
  State<MachineSelectionScreen> createState() => _MachineSelectionScreenState();
}

class _MachineSelectionScreenState extends State<MachineSelectionScreen> {
  static final Map<String, String> _muscleNameById = <String, String>{
    for (final m in MasterData.muscles) m.id: m.name,
  };

  late Set<String> _draftMachineIds;
  Gym? _draftGym;
  bool _isEditingGymMaster = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _draftMachineIds = Set<String>.from(widget.appState.availableMachineIds);
    _draftGym = widget.appState.selectedGym;
  }

  void _showMinimumOneAlert() {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text(
            '最低1台以上のマシンを選択してください',
            style: TextStyle(
              color: AppColors.onError,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
  }

  void _toggleMachine(String machineId) {
    setState(() {
      if (_draftMachineIds.contains(machineId)) {
        if (_draftMachineIds.length <= 1) {
          _showMinimumOneAlert();
          return;
        }
        _draftMachineIds.remove(machineId);
      } else {
        _draftMachineIds.add(machineId);
      }
    });
  }

  void _toggleCategory(MuscleGroup group, bool selectAll) {
    final groupIds = MasterData.machines
        .where((m) => m.category == group)
        .map((m) => m.id)
        .toSet();
    setState(() {
      if (selectAll) {
        _draftMachineIds.addAll(groupIds);
      } else {
        final next = Set<String>.from(_draftMachineIds)..removeAll(groupIds);
        if (next.isEmpty) {
          _showMinimumOneAlert();
          return;
        }
        _draftMachineIds = next;
      }
    });
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    if (_isEditingGymMaster && _draftGym != null) {
      await _confirmAndUpdateGymMachines();
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await widget.appState.saveMachineSelection(
        machineIds: _draftMachineIds,
        selectedGym: _draftGym,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _enterGymMasterEditMode() {
    final gym = _draftGym;
    if (gym == null) return;
    setState(() {
      _isEditingGymMaster = true;
      _draftMachineIds = Set<String>.from(gym.machineIds);
    });
  }

  Future<void> _confirmAndUpdateGymMachines() async {
    final gym = _draftGym;
    if (gym == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('confirm_update_gym_dialog'),
          backgroundColor: AppColors.surface,
          title: const Text(
            'ジムの機材リストを更新しますか？',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            '「${gym.name}」の共有機材リスト（選択中: ${_draftMachineIds.length}台）を更新して保存します。この変更は他のユーザーにも反映されます。',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              key: const Key('btn_cancel_update_gym'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'キャンセル',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              key: const Key('btn_confirm_update_gym'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.tealAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '更新して保存',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSaving = true;
    });
    try {
      final updatedGym = await widget.appState.updateGymMachines(
        gym.id,
        _draftMachineIds,
      );
      if (!mounted) return;
      setState(() {
        _draftGym = updatedGym;
        _draftMachineIds = Set<String>.from(updatedGym.machineIds);
        _isEditingGymMaster = false;
      });
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: AppColors.highlightSelectedSurface,
            content: Text(
              '「${updatedGym.name}」の機材リストを更新しました',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showGymSearchSheet() async {
    final initialResults = await widget.appState.searchGyms('');
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return _GymSearchSheet(
          appState: widget.appState,
          initialResults: initialResults,
          draftMachineIds: _draftMachineIds,
          onSelectGym: (gym) {
            setState(() {
              _draftGym = gym;
              _draftMachineIds = Set<String>.from(gym.machineIds);
              _isEditingGymMaster = false;
            });
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  String _formatTargetMuscles(Machine machine) {
    final names = machine.primaryMuscleIds
        .map((id) => _muscleNameById[id] ?? id)
        .toList();
    return names.join('・');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          key: const Key('btn_back_machine_selection'),
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'マシンを選択',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('btn_save_machines'),
            onPressed: _isSaving ? null : _handleSave,
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.tealAccent,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('machine_selection_list'),
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildGymSearchCard(),
                  if (_isEditingGymMaster && _draftGym != null) ...[
                    const SizedBox(height: 12),
                    _buildGymEditingBanner(_draftGym!),
                  ],
                  const SizedBox(height: 16),
                  for (final group in MuscleGroup.values) ...[
                    _buildCategorySection(group: group),
                    if (group != MuscleGroup.values.last)
                      const SizedBox(height: 16),
                  ],
                  if (_draftGym != null) ...[
                    const SizedBox(height: 20),
                    _buildBottomGymAction(_draftGym!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGymSearchCard() {
    final selectedGym = _draftGym;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selectedGym != null ? AppColors.tealAccent : AppColors.border,
        ),
      ),
      child: InkWell(
        key: const Key('btn_search_gym'),
        borderRadius: BorderRadius.circular(14),
        onTap: _showGymSearchSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.search,
                color: AppColors.tealAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ジムを検索',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedGym != null
                          ? '選択中のジム: ${selectedGym.name}'
                          : '利用する店舗を検索・登録します',
                      style: TextStyle(
                        fontSize: 12,
                        color: selectedGym != null
                            ? AppColors.tealAccent
                            : AppColors.textSecondary,
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

  Widget _buildGymEditingBanner(Gym gym) {
    return Container(
      key: const Key('gym_master_editing_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.highlightEditingSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amberAccent),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.edit_note,
            color: AppColors.amberAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '「${gym.name}」の店舗機材リストを編集中です',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _isEditingGymMaster = false;
                _draftMachineIds = Set<String>.from(
                  widget.appState.availableMachineIds,
                );
              });
            },
            child: const Text(
              '中止',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection({required MuscleGroup group}) {
    final machines = MasterData.machines
        .where((m) => m.category == group)
        .toList();
    final selectedInGroup = machines
        .where((m) => _draftMachineIds.contains(m.id))
        .length;
    final allInGroupSelected = selectedInGroup == machines.length;

    return Container(
      key: Key('machine_group_${group.name}'),
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  '${group.label}（$selectedInGroup / ${machines.length}）',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.tealAccent,
                  ),
                ),
              ),
              TextButton(
                key: Key('machine_group_toggle_${group.name}'),
                onPressed: () => _toggleCategory(group, !allInGroupSelected),
                style: TextButton.styleFrom(
                  foregroundColor: allInGroupSelected
                      ? AppColors.textSecondary
                      : AppColors.tealAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  allInGroupSelected ? 'すべて解除' : 'すべて選択',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < machines.length; i++) ...[
            _buildMachineCard(
              machine: machines[i],
              isAvailable: _draftMachineIds.contains(machines[i].id),
            ),
            if (i < machines.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildMachineCard({
    required Machine machine,
    required bool isAvailable,
  }) {
    final targetMuscles = _formatTargetMuscles(machine);

    return Material(
      color: isAvailable
          ? AppColors.highlightSelectedSurface
          : AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAvailable ? AppColors.tealAccent : AppColors.border,
          width: isAvailable ? 1.2 : 1.0,
        ),
      ),
      child: InkWell(
        key: Key('machine_toggle_${machine.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleMachine(machine.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isAvailable
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: isAvailable
                    ? AppColors.tealAccent
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      machine.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isAvailable
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (targetMuscles.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '主働筋: $targetMuscles',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGymAction(Gym gym) {
    if (_isEditingGymMaster) {
      return FilledButton.icon(
        key: const Key('btn_update_gym_machines'),
        icon: const Icon(Icons.cloud_upload_outlined),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amberAccent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _isSaving ? null : _confirmAndUpdateGymMachines,
        label: Text(
          '「${gym.name}」の機材リストを更新する',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      );
    }

    return OutlinedButton.icon(
      key: const Key('btn_edit_gym_machines'),
      icon: const Icon(Icons.edit_outlined),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: _enterGymMasterEditMode,
      label: const Text(
        '店舗の機材リストを変更する',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _GymSearchSheet extends StatefulWidget {
  final AppState appState;
  final List<Gym> initialResults;
  final Set<String> draftMachineIds;
  final ValueChanged<Gym> onSelectGym;

  const _GymSearchSheet({
    required this.appState,
    required this.initialResults,
    required this.draftMachineIds,
    required this.onSelectGym,
  });

  @override
  State<_GymSearchSheet> createState() => _GymSearchSheetState();
}

class _GymSearchSheetState extends State<_GymSearchSheet> {
  /// カタカナ・ひらがな・漢字（および長音符・踊り字）のみ許可
  static final RegExp _japaneseOnlyRegex = RegExp(
    r'^[\u3040-\u309F\u30A0-\u30FF\u30FC\u3005\u4E00-\u9FFF\u3400-\u4DBF]+$',
  );

  late final TextEditingController _controller;
  late List<Gym> _results;
  String? _errorText;
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _results = widget.initialResults;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String value) async {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !_japaneseOnlyRegex.hasMatch(trimmed)) {
      setState(() {
        _errorText = 'カタカナ・ひらがな・漢字のみ入力できます';
      });
      return;
    }
    setState(() {
      _errorText = null;
      _isSearching = true;
    });
    final found = await widget.appState.searchGyms(trimmed);
    if (!mounted) return;
    setState(() {
      _results = found;
      _isSearching = false;
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final isValidInput = query.isEmpty || _japaneseOnlyRegex.hasMatch(query);
    final hasExactMatch = _results.any((g) => g.name == query);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
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
              'ジムを検索',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '店舗名を入力してください（カタカナ・ひらがな・漢字のみ）',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('gym_search_input'),
                    controller: _controller,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '例：エニタイム渋谷',
                      errorText: _errorText,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.tealAccent,
                      ),
                    ),
                    onChanged: (value) {
                      final trimmed = value.trim();
                      setState(() {
                        if (trimmed.isNotEmpty &&
                            !_japaneseOnlyRegex.hasMatch(trimmed)) {
                          _errorText = 'カタカナ・ひらがな・漢字のみ入力できます';
                        } else {
                          _errorText = null;
                        }
                      });
                    },
                    onSubmitted: _runSearch,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  height: 48,
                  child: FilledButton(
                    key: const Key('btn_execute_gym_search'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tealAccent,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: isValidInput && !_isSearching
                        ? () => _runSearch(_controller.text)
                        : null,
                    child: const Text(
                      '検索',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_results.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final gym = _results[index];
                      return Material(
                        color: AppColors.surfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: InkWell(
                          key: Key('gym_search_result_${gym.id}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onSelectGym(gym),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.storefront_outlined,
                                  color: AppColors.tealAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    gym.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${gym.machineIds.length}台',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else if (_hasSearched)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '該当する店舗が見つかりませんでした。下のボタンから新しい店舗として登録できます。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (query.isNotEmpty && isValidInput && !hasExactMatch) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('btn_register_gym'),
                  icon: const Icon(Icons.add_business_outlined),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.tealAccent,
                    side: const BorderSide(color: AppColors.tealAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    final created = await widget.appState.registerGym(
                      query,
                      widget.draftMachineIds,
                    );
                    if (!mounted) return;
                    widget.onSelectGym(created);
                  },
                  label: Text(
                    '「$query」を新しい店舗として登録する',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
