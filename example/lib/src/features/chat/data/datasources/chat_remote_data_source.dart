import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/chat_connection_settings.dart';

final class ChatRemoteDataSource {
  ChatRemoteDataSource({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Stream<String> streamAnswer(ChatCompletionRequest request) {
    return switch (request.settings.provider) {
      ChatProvider.ollama => _streamOllama(request),
      ChatProvider.openai => _streamOpenAICompatible(request),
      ChatProvider.xai => _streamOpenAICompatible(request),
      ChatProvider.anthropic => _streamAnthropic(request),
      ChatProvider.gemini => _streamGemini(request),
    };
  }

  Stream<String> _streamOpenAICompatible(ChatCompletionRequest request) async* {
    final ChatConnectionSettings settings = request.settings;
    _requireApiKey(settings);
    final http.StreamedResponse response = await _postJson(
      _resolve(settings.baseUrl, '/v1/chat/completions'),
      headers: <String, String>{
        'Authorization': 'Bearer ${settings.apiKey.trim()}',
      },
      body: <String, Object?>{
        'model': settings.model.trim(),
        'stream': true,
        'think': false,
        'messages': _openAICompatibleMessages(request),
      },
    );

    yield* _readSseJson(response, (Map<String, dynamic> json) {
      final Object? choices = json['choices'];
      if (choices is! List || choices.isEmpty) {
        return '';
      }
      final Object? first = choices.first;
      if (first is! Map<String, dynamic>) {
        return '';
      }
      final Object? delta = first['delta'];
      if (delta is Map<String, dynamic> && delta['content'] is String) {
        return delta['content'] as String;
      }
      return '';
    });
  }

  Stream<String> _streamOllama(ChatCompletionRequest request) async* {
    final ChatConnectionSettings settings = request.settings;
    final http.StreamedResponse response = await _postJson(
      _resolve(settings.baseUrl, '/api/chat'),
      body: <String, Object?>{
        'model': settings.model.trim(),
        'stream': true,
        'messages': _openAICompatibleMessages(request),
      },
    );

    await for (final String line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) {
        continue;
      }
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final Object? message = decoded['message'];
      if (message is Map<String, dynamic> && message['content'] is String) {
        yield message['content'] as String;
      }
      if (decoded['done'] == true) {
        break;
      }
    }
  }

  Stream<String> _streamAnthropic(ChatCompletionRequest request) async* {
    final ChatConnectionSettings settings = request.settings;
    _requireApiKey(settings);
    final http.StreamedResponse response = await _postJson(
      _resolve(settings.baseUrl, '/v1/messages'),
      headers: <String, String>{
        'x-api-key': settings.apiKey.trim(),
        'anthropic-version': '2023-06-01',
      },
      body: <String, Object?>{
        'model': settings.model.trim(),
        'max_tokens': 4096,
        'stream': true,
        if (settings.systemPrompt.trim().isNotEmpty)
          'system': settings.systemPrompt.trim(),
        'messages': request.messages
            .where((ChatMessage message) => message.role != 'system')
            .map(
              (ChatMessage message) => <String, String>{
                'role': message.role == 'assistant' ? 'assistant' : 'user',
                'content': message.content,
              },
            )
            .toList(growable: false),
      },
    );

    yield* _readSseJson(response, (Map<String, dynamic> json) {
      if (json['type'] != 'content_block_delta') {
        return '';
      }
      final Object? delta = json['delta'];
      if (delta is Map<String, dynamic> && delta['text'] is String) {
        return delta['text'] as String;
      }
      return '';
    });
  }

  Stream<String> _streamGemini(ChatCompletionRequest request) async* {
    final ChatConnectionSettings settings = request.settings;
    _requireApiKey(settings);
    final Uri base = _resolve(
      settings.baseUrl,
      '/v1beta/models/${settings.model.trim()}:streamGenerateContent',
    );
    final Uri uri = base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'alt': 'sse',
        'key': settings.apiKey.trim(),
      },
    );
    final http.StreamedResponse response = await _postJson(
      uri,
      body: <String, Object?>{
        if (settings.systemPrompt.trim().isNotEmpty)
          'systemInstruction': <String, Object?>{
            'parts': <Object>[
              <String, String>{'text': settings.systemPrompt.trim()},
            ],
          },
        'contents': request.messages
            .map(
              (ChatMessage message) => <String, Object?>{
                'role': message.role == 'assistant' ? 'model' : 'user',
                'parts': <Object>[
                  <String, String>{'text': message.content},
                ],
              },
            )
            .toList(growable: false),
      },
    );

    yield* _readSseJson(response, (Map<String, dynamic> json) {
      final Object? candidates = json['candidates'];
      if (candidates is! List) {
        return '';
      }
      final StringBuffer buffer = StringBuffer();
      for (final Object? candidate in candidates) {
        if (candidate is! Map<String, dynamic>) {
          continue;
        }
        final Object? content = candidate['content'];
        if (content is! Map<String, dynamic>) {
          continue;
        }
        final Object? parts = content['parts'];
        if (parts is! List) {
          continue;
        }
        for (final Object? part in parts) {
          if (part is Map<String, dynamic> && part['text'] is String) {
            buffer.write(part['text']);
          }
        }
      }
      return buffer.toString();
    });
  }

  Future<http.StreamedResponse> _postJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    required Map<String, Object?> body,
  }) async {
    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(<String, String>{
        'Content-Type': 'application/json',
        ...headers,
      })
      ..bodyBytes = utf8.encode(jsonEncode(body));

    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final String responseBody = await response.stream.bytesToString();
    throw StateError(
      'HTTP ${response.statusCode}: ${_extractError(responseBody)}',
    );
  }

  List<Map<String, String>> _openAICompatibleMessages(
    ChatCompletionRequest request,
  ) {
    final List<Map<String, String>> messages = <Map<String, String>>[];
    if (request.settings.systemPrompt.trim().isNotEmpty) {
      messages.add(<String, String>{
        'role': 'system',
        'content': request.settings.systemPrompt.trim(),
      });
    }
    messages.addAll(
      request.messages.map(
        (ChatMessage message) => <String, String>{
          'role': message.role,
          'content': message.content,
        },
      ),
    );
    return messages;
  }

  Stream<String> _readSseJson(
    http.StreamedResponse response,
    String Function(Map<String, dynamic> json) extract,
  ) async* {
    final List<String> eventDataLines = <String>[];
    await for (final String line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (eventDataLines.isNotEmpty) {
          final String chunk = _extractSseChunk(eventDataLines, extract);
          eventDataLines.clear();
          if (chunk.isNotEmpty) {
            yield chunk;
          }
        }
        continue;
      }
      if (line.startsWith('data:')) {
        eventDataLines.add(line.substring(5).trimLeft());
      }
    }
    if (eventDataLines.isNotEmpty) {
      final String chunk = _extractSseChunk(eventDataLines, extract);
      if (chunk.isNotEmpty) {
        yield chunk;
      }
    }
  }

  String _extractSseChunk(
    List<String> eventDataLines,
    String Function(Map<String, dynamic> json) extract,
  ) {
    final String payload = eventDataLines.join('\n').trim();
    if (payload.isEmpty || payload == '[DONE]') {
      return '';
    }
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return extract(decoded);
    }
    return '';
  }

  Uri _resolve(String baseUrl, String path) {
    final Uri base = Uri.parse(baseUrl.trim());
    return base.replace(path: path);
  }

  void _requireApiKey(ChatConnectionSettings settings) {
    if (settings.apiKey.trim().isEmpty) {
      throw StateError('${settings.provider.label} requires an API key.');
    }
  }

  String _extractError(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final Object? error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) {
          return decoded['message'] as String;
        }
      }
    } catch (_) {
      return body;
    }
    return body;
  }

  void dispose() {
    _httpClient.close();
  }
}
