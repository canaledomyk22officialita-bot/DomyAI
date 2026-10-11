import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'engine.dart';

/// Server HTTP compatibile con l'API OpenAI (/v1/models, /v1/chat/completions).
class AiServer {
  AiServer(this.engine, {required this.systemPrompt, this.apiKey = '', this.onLog});

  final LlmEngine engine;
  final String systemPrompt;
  final String apiKey;
  final void Function(String)? onLog;
  HttpServer? _http;
  bool _busy = false;

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  Future<void> start(int port) async {
    final router = Router()
      ..get('/', (Request r) => Response.ok('DomyAI server attivo'))
      ..get('/v1/models', _models)
      ..post('/v1/chat/completions', _chat);
    final handler = const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_auth())
        .addHandler(router.call);
    _http = await io.serve(handler, InternetAddress.anyIPv4, port);
    onLog?.call('Server avviato sulla porta $port');
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    engine.dispose();
  }

  Middleware _cors() => (inner) => (req) async {
        const h = {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'access-control-allow-private-network': 'true',
        };
        if (req.method == 'OPTIONS') return Response(204, headers: h);
        final res = await inner(req);
        return res.change(headers: h);
      };

  Middleware _auth() => (inner) => (req) {
        if (apiKey.isEmpty || req.url.path.isEmpty) return inner(req);
        if (req.headers['authorization'] != 'Bearer $apiKey') {
          return _err(401, 'API key non valida');
        }
        return inner(req);
      };

  Response _err(int code, String msg) => Response(code,
      body: jsonEncode({'error': {'message': msg}}), headers: _json);

  Response _models(Request r) => Response.ok(
      jsonEncode({
        'object': 'list',
        'data': [
          {'id': 'domyai', 'object': 'model', 'owned_by': 'local'}
        ]
      }),
      headers: _json);

  Future<Response> _chat(Request req) async {
    if (_busy) return _err(429, 'Server occupato, riprova tra poco');
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _err(400, 'JSON non valido');
    }
    final msgs = (body['messages'] as List?) ?? const [];
    final maxTokens = (body['max_tokens'] as num?)?.toInt() ?? 512;
    final temp = (body['temperature'] as num?)?.toDouble() ?? 0.7;
    final stream = body['stream'] == true;
    final id = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    onLog?.call('Richiesta: ${msgs.length} messaggi, stream=$stream');

    _busy = true;
    final tokens = _tokens(_prompt(msgs), maxTokens, temp);

    if (!stream) {
      final text = await tokens.join();
      return Response.ok(
          jsonEncode({
            'id': id,
            'object': 'chat.completion',
            'created': created,
            'model': 'domyai',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': text},
                'finish_reason': 'stop'
              }
            ]
          }),
          headers: _json);
    }

    final sse = (() async* {
      await for (final t in tokens) {
        yield _chunk(id, created, {'content': t}, null);
      }
      yield _chunk(id, created, {}, 'stop');
      yield 'data: [DONE]\n\n';
    })();
    return Response.ok(sse.map(utf8.encode),
        headers: {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
        },
        context: {'shelf.io.buffer_output': false});
  }

  Stream<String> _tokens(String prompt, int maxTokens, double temp) async* {
    try {
      yield* engine.generate(prompt, maxTokens: maxTokens, temperature: temp);
    } finally {
      _busy = false;
    }
  }

  String _chunk(String id, int created, Map delta, String? finish) =>
      'data: ${jsonEncode({
            'id': id,
            'object': 'chat.completion.chunk',
            'created': created,
            'model': 'domyai',
            'choices': [
              {'index': 0, 'delta': delta, 'finish_reason': finish}
            ]
          })}\n\n';

  /// Formato ChatML (Qwen, e molti altri modelli). Cambialo se usi un modello diverso.
  String _prompt(List msgs) {
    final sys = StringBuffer(systemPrompt);
    final turns = StringBuffer();
    for (final m in msgs) {
      final role = (m['role'] as String?) ?? 'user';
      final text = _text(m['content']);
      if (role == 'system') {
        sys.write('\n$text');
      } else {
        turns.write('<|im_start|>$role\n$text<|im_end|>\n');
      }
    }
    return '<|im_start|>system\n$sys<|im_end|>\n$turns<|im_start|>assistant\n';
  }

  String _text(dynamic c) => c is String
      ? c
      : c is List
          ? c.map((p) => p is Map ? (p['text'] ?? '') : '').join()
          : '';
}
