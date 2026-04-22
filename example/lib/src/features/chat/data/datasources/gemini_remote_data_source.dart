import 'dart:convert';
import 'dart:io';

final class GeminiRemoteDataSource {
  GeminiRemoteDataSource({
    required this.apiKey,
    required this.model,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final String apiKey;
  final String model;
  final HttpClient _httpClient;

  Stream<String> streamAnswer(String question) async* {
    if (apiKey.trim().isEmpty) {
      throw StateError('Missing GEMINI_API_KEY in .env or --dart-define.');
    }

    final Uri uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:streamGenerateContent',
      <String, String>{'alt': 'sse', 'key': apiKey},
    );
    final HttpClientRequest request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'contents': <Object>[
            <String, Object?>{
              'role': 'user',
              'parts': <Object>[
                <String, String>{'text': question},
              ],
            },
          ],
        }),
      ),
    );

    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String body = await response.transform(utf8.decoder).join();
      throw StateError('HTTP ${response.statusCode}: ${_extractError(body)}');
    }

    final List<String> eventDataLines = <String>[];
    final Stream<String> lineStream = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final String line in lineStream) {
      if (line.isEmpty) {
        if (eventDataLines.isNotEmpty) {
          final String eventData = eventDataLines.join('\n');
          eventDataLines.clear();
          if (eventData == '[DONE]') {
            break;
          }
          final String chunk = _extractEventChunk(eventData);
          if (chunk.isNotEmpty) {
            yield chunk;
          }
        }
        continue;
      }

      if (!line.startsWith('data:')) {
        continue;
      }
      eventDataLines.add(line.substring(5).trimLeft());
    }

    if (eventDataLines.isNotEmpty) {
      final String finalEventData = eventDataLines.join('\n');
      final String chunk = _extractEventChunk(finalEventData);
      if (chunk.isNotEmpty) {
        yield chunk;
      }
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }

  String _extractEventChunk(String eventData) {
    final String payload = eventData.trim();
    if (payload.isEmpty || payload == '[DONE]') {
      return '';
    }

    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    final Object? candidates = decoded['candidates'];
    if (candidates is! List<dynamic>) {
      return '';
    }

    final StringBuffer text = StringBuffer();
    for (final Object? candidate in candidates) {
      if (candidate is! Map<String, dynamic>) {
        continue;
      }
      final Object? content = candidate['content'];
      if (content is! Map<String, dynamic>) {
        continue;
      }
      final Object? parts = content['parts'];
      if (parts is! List<dynamic>) {
        continue;
      }
      for (final Object? part in parts) {
        if (part is! Map<String, dynamic>) {
          continue;
        }
        final Object? partText = part['text'];
        if (partText is String && partText.isNotEmpty) {
          text.write(partText);
        }
      }
    }

    return text.toString();
  }

  String _extractError(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return body;
      }
      final Object? error = decoded['error'];
      if (error is! Map<String, dynamic>) {
        return body;
      }
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    } catch (_) {
      return body;
    }
    return body;
  }
}
