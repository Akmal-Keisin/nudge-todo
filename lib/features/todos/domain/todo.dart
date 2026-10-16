import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Sentinel so [Todo.copyWith] can tell "leave archivedAt alone" from
/// "clear archivedAt to null".
const Object _unset = Object();

class Todo {
  Todo({
    String? id,
    required this.text,
    this.isArchived = false,
    this.archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String text;
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Todo copyWith({String? text, bool? isArchived, Object? archivedAt = _unset}) {
    return Todo(
      id: id,
      text: text ?? this.text,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: identical(archivedAt, _unset)
          ? this.archivedAt
          : archivedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Todo archive() =>
      copyWith(isArchived: true, archivedAt: DateTime.now().toUtc());

  Todo restore() => copyWith(isArchived: false, archivedAt: null);

  bool get isExpired {
    if (!isArchived || archivedAt == null) return false;
    return DateTime.now().toUtc().difference(archivedAt!).inDays >= 14;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isArchived': isArchived,
    'archivedAt': archivedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    id: json['id'] as String,
    text: json['text'] as String,
    isArchived: json['isArchived'] as bool,
    archivedAt: json['archivedAt'] != null
        ? DateTime.parse(json['archivedAt'] as String)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  static const maxLength = 500;
  static const archiveRetentionDays = 14;
}
