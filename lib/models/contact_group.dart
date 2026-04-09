/// A named group of phone numbers stored in Hive.
library;

import 'package:hive_flutter/hive_flutter.dart';

part 'contact_group.g.dart';

@HiveType(typeId: 0)
class ContactGroup extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String name;

  @HiveField(2)
  late List<String> numbers; // E.164

  @HiveField(3)
  late DateTime createdAt;

  ContactGroup({
    required this.id,
    required this.name,
    required this.numbers,
    required this.createdAt,
  });

  ContactGroup copyWith({
    String? id,
    String? name,
    List<String>? numbers,
    DateTime? createdAt,
  }) =>
      ContactGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        numbers: numbers ?? List.from(this.numbers),
        createdAt: createdAt ?? this.createdAt,
      );
}
