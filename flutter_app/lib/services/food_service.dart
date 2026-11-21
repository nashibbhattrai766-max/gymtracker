import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class FoodEstimateItem {
  String name;
  String portion;
  double kcal;
  double proteinG;
  FoodEstimateItem({required this.name, this.portion = '', required this.kcal, required this.proteinG});

  factory FoodEstimateItem.fromJson(Map<String, dynamic> j) => FoodEstimateItem(
        name: j['name'] ?? 'Food',
        portion: j['portion'] ?? '',
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
      );
}

class FoodEstimate {
  final List<FoodEstimateItem> items;
  final String confidence;
  final String note;
  FoodEstimate(this.items, this.confidence, this.note);
}

/// Sends a meal photo to the backend (which asks Groq's vision model) and
/// returns the estimated foods. The photo itself is not stored anywhere.
class FoodService {
  static Future<FoodEstimate> analyse(List<int> jpegBytes, {required String meal}) async {
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/ai/food-photo'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image_base64': base64Encode(jpegBytes),
            'mime_type': 'image/jpeg',
            'meal': meal,
          }),
        )
        .timeout(const Duration(seconds: 75));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['detail'] ?? 'Server returned ${res.statusCode}');
    }
    return FoodEstimate(
      ((body['items'] as List?) ?? const [])
          .map((e) => FoodEstimateItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      body['confidence'] ?? 'medium',
      body['note'] ?? '',
    );
  }
}
