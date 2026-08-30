import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../features/chat/domain/models/chat_connection_settings.dart';

final class AppEnv {
  AppEnv._();

  static ChatConnectionSettings get initialChatSettings {
    final ChatProvider provider = _provider(
      _string('CHAT_PROVIDER', fallback: 'ollama'),
    );
    return ChatConnectionSettings.defaults(provider).copyWith(
      model: _string('CHAT_MODEL', fallback: _legacyModelFallback(provider)),
      baseUrl: _string('CHAT_BASE_URL', fallback: provider.defaultBaseUrl),
      apiKey: _apiKey(provider),
      systemPrompt: _string(
        'CHAT_SYSTEM_PROMPT',
        fallback:
            'You are a helpful assistant. Reply in Markdown when formatting helps.',
      ),
    );
  }

  static ChatProvider _provider(String value) {
    final String normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'chatgpt' || 'openai' => ChatProvider.openai,
      'claude' || 'anthropic' => ChatProvider.anthropic,
      'gemini' || 'google' => ChatProvider.gemini,
      'grok' || 'xai' => ChatProvider.xai,
      _ => ChatProvider.ollama,
    };
  }

  static String _apiKey(ChatProvider provider) {
    return switch (provider) {
      ChatProvider.ollama => '',
      ChatProvider.openai => _string('OPENAI_API_KEY'),
      ChatProvider.anthropic => _string('ANTHROPIC_API_KEY'),
      ChatProvider.gemini => _string(
          'GEMINI_API_KEY',
          fallback: _string('GOOGLE_API_KEY'),
        ),
      ChatProvider.xai => _string('XAI_API_KEY'),
    };
  }

  static String _legacyModelFallback(ChatProvider provider) {
    if (provider == ChatProvider.gemini) {
      return _string('GEMINI_MODEL', fallback: provider.defaultModel);
    }
    return provider.defaultModel;
  }

  static String _string(String name, {String fallback = ''}) {
    final String fromDotenv = _dotenvValue(name);
    if (fromDotenv.isNotEmpty) {
      return fromDotenv;
    }
    final String fromDefine = switch (name) {
      'CHAT_PROVIDER' => const String.fromEnvironment('CHAT_PROVIDER'),
      'CHAT_MODEL' => const String.fromEnvironment('CHAT_MODEL'),
      'CHAT_BASE_URL' => const String.fromEnvironment('CHAT_BASE_URL'),
      'CHAT_SYSTEM_PROMPT' => const String.fromEnvironment(
          'CHAT_SYSTEM_PROMPT',
        ),
      'OPENAI_API_KEY' => const String.fromEnvironment('OPENAI_API_KEY'),
      'ANTHROPIC_API_KEY' => const String.fromEnvironment('ANTHROPIC_API_KEY'),
      'GEMINI_API_KEY' => const String.fromEnvironment('GEMINI_API_KEY'),
      'GOOGLE_API_KEY' => const String.fromEnvironment('GOOGLE_API_KEY'),
      'GEMINI_MODEL' => const String.fromEnvironment('GEMINI_MODEL'),
      'XAI_API_KEY' => const String.fromEnvironment('XAI_API_KEY'),
      _ => '',
    }
        .trim();
    return fromDefine.isNotEmpty ? fromDefine : fallback;
  }

  static String _dotenvValue(String name) {
    try {
      return dotenv.maybeGet(name)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
