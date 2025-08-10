import 'package:smartreceipt/domain/entities/receipt.dart';

abstract class AiTaggingService {
  Future<List<String>> suggestTags(Receipt receipt);
}


