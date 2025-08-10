import 'package:smartreceipt/data/services/ai/ai_tagging_service.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';

class OpenAiTaggerStub implements AiTaggingService {
  @override
  Future<List<String>> suggestTags(Receipt receipt) async {
    final String lower = receipt.storeName.toLowerCase();
    if (lower.contains('best') || lower.contains('target')) {
      return <String>['Electronics', 'Retail'];
    }
    if (lower.contains('tesco') || lower.contains('coles')) {
      return <String>['Groceries'];
    }
    return <String>['General'];
  }
}


