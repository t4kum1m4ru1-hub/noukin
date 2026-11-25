bool _setEquals(Set<String> a, Set<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

/// ジム店舗と紐づく機材リスト
class Gym {
  final String id;
  final String name;
  final Set<String> machineIds;
  final DateTime? updatedAt;

  const Gym({
    required this.id,
    required this.name,
    required this.machineIds,
    this.updatedAt,
  });

  Gym copyWith({
    String? id,
    String? name,
    Set<String>? machineIds,
    DateTime? updatedAt,
  }) {
    return Gym(
      id: id ?? this.id,
      name: name ?? this.name,
      machineIds: machineIds ?? this.machineIds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    final sorted = machineIds.toList()..sort();
    return <String, dynamic>{
      'id': id,
      'name': name,
      'machine_ids': sorted,
      if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
    };
  }

  factory Gym.fromJson(Map<String, dynamic> json) {
    final rawIds = json['machine_ids'] ?? json['machineIds'];
    final parsedIds = <String>{};
    if (rawIds is List) {
      for (final item in rawIds) {
        if (item is String && item.trim().isNotEmpty) {
          parsedIds.add(item);
        }
      }
    }
    final rawUpdatedAt = json['updated_at'] ?? json['updatedAt'];
    DateTime? updatedAt;
    if (rawUpdatedAt is String && rawUpdatedAt.isNotEmpty) {
      updatedAt = DateTime.tryParse(rawUpdatedAt);
    }

    return Gym(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      machineIds: parsedIds,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Gym &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          _setEquals(machineIds, other.machineIds) &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, Object.hashAllUnordered(machineIds), updatedAt);
}
