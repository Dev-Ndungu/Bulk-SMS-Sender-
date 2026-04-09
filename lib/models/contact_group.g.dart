// GENERATED CODE – DO NOT MODIFY BY HAND (written manually for this project)
// ignore_for_file: type=lint

part of 'contact_group.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ContactGroupAdapter extends TypeAdapter<ContactGroup> {
  @override
  final int typeId = 0;

  @override
  ContactGroup read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContactGroup(
      id: fields[0] as String,
      name: fields[1] as String,
      numbers: (fields[2] as List).cast<String>(),
      createdAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ContactGroup obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.numbers)
      ..writeByte(3)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactGroupAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
