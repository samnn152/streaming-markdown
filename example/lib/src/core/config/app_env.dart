import 'package:flutter_dotenv/flutter_dotenv.dart';

final class AppEnv {
  AppEnv._();

  static String get geminiApiKey {
    final String fromDotenv = dotenv.maybeGet('GEMINI_API_KEY')?.trim() ?? '';
    if (fromDotenv.isNotEmpty) {
      return fromDotenv;
    }
    const String fromDefine = String.fromEnvironment('GEMINI_API_KEY');
    return fromDefine;
  }

  static String get geminiModel {
    final String fromDotenv = dotenv.maybeGet('GEMINI_MODEL')?.trim() ?? '';
    if (fromDotenv.isNotEmpty) {
      return fromDotenv;
    }
    const String fromDefine = String.fromEnvironment(
      'GEMINI_MODEL',
      defaultValue: 'gemini-2.0-flash',
    );
    return fromDefine;
  }
}
