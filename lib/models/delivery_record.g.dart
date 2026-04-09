// GENERATED CODE – DO NOT MODIFY BY HAND (written manually for this project)
// ignore_for_file: type=lint

part of 'delivery_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DeliveryRecordAdapter extends TypeAdapter<DeliveryRecord> {
  @override
  final int typeId = 1;

  @override
  DeliveryRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DeliveryRecord(
      jobId: fields[0] as String,
      number: fields[1] as String,
      messageBody: fields[2] as String,
      sentAt: fields[4] as DateTime,
      gatewayMessageId: fields[5] as String?,
      errorMessage: fields[6] as String?,
    )..statusStr = fields[3] as String;
  }

  @override
  void write(BinaryWriter writer, DeliveryRecord obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.jobId)
      ..writeByte(1)
      ..write(obj.number)
      ..writeByte(2)
      ..write(obj.messageBody)
      ..writeByte(3)
      ..write(obj.statusStr)
      ..writeByte(4)
      ..write(obj.sentAt)
      ..writeByte(5)
      ..write(obj.gatewayMessageId)
      ..writeByte(6)
      ..write(obj.errorMessage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
