import 'dart:async';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

abstract class LlmEngine {
  Future<void> load(String modelPath, {int contextSize = 2048});
  Stream<String> generate(String prompt, {int maxTokens = 512, double temperature = 0.7});
  void dispose();
}

/// Motore reale: llama.cpp tramite il pacchetto llama_cpp_dart.
/// ATTENZIONE: l'API di llama_cpp_dart cambia tra le versioni.
/// Se non compila, correggi SOLO questa classe: il resto dell'app non dipende da lei.
class LlamaEngine implements LlmEngine {
  Llama? _llama;

  @override
  Future<void> load(String modelPath, {int contextSize = 2048}) async {
    Llama.libraryPath = 'libllama.so';
    final ctx = ContextParams()..nCtx = contextSize;
    _llama = Llama(modelPath, ModelParams(), ctx, SamplerParams());
  }

  @override
  Stream<String> generate(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async* {
    final l = _llama;
    if (l == null) throw StateError('Modello non caricato');
    l.clear();
    l.setPrompt(prompt);
    for (var i = 0; i < maxTokens; i++) {
      final (token, done) = l.getNext();
      if (done) break;
      yield token;
      // Lascia respirare l'event loop tra un token e l'altro.
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() => _llama?.dispose();
}

/// Motore finto per provare server, rete e client senza modello.
class MockEngine implements LlmEngine {
  @override
  Future<void> load(String modelPath, {int contextSize = 2048}) async {}

  @override
  Stream<String> generate(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async* {
    const text = 'Modalità test: il server funziona. '
        'Scegli un modello .gguf e spegni la modalità test per risposte vere.';
    for (final w in text.split(' ')) {
      yield '$w ';
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  void dispose() {}
}
