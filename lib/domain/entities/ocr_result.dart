import 'package:equatable/equatable.dart';

class OcrResult extends Equatable {
  const OcrResult({
    this.storeName,
    this.total,
    this.date,
    this.rawText,
  });

  final String? storeName;
  final double? total;
  final DateTime? date;
  final String? rawText;

  @override
  List<Object?> get props => [storeName, total, date, rawText];
}