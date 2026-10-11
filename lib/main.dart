import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'engine.dart';
import 'server.dart';

void main() => runApp(const DomyAiApp());

class DomyAiApp extends StatelessWidget {
  const DomyAiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DomyAI Server',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2F4BFF), useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF2F4BFF),
            brightness: Brightness.dark,
            useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _port = TextEditingController(text: '8080');
  final _key = TextEditingController();
  final _system = TextEditingController(
      text: 'Sei un assistente per programmatori. Rispondi in italiano, in modo chiaro e con codice corretto.');
  String? _model;
  List<String> _models = [];
  String _dir = '';
  bool _test = false, _running = false;
  String _status = 'Fermo';
  final List<String> _log = [];
  AiServer? _server;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _port.text = p.getString('port') ?? _port.text;
    _key.text = p.getString('key') ?? '';
    _system.text = p.getString('system') ?? _system.text;
    _model = p.getString('model');
    _test = p.getBool('test') ?? false;
    final d = await getExternalStorageDirectory();
    if (d != null) {
      _dir = d.path;
      _scan();
    }
    setState(() {});
  }

  void _scan() {
    _models = Directory(_dir)
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.toLowerCase().endsWith('.gguf'))
        .toList();
  }

  void _addLog(String m) {
    if (!mounted) return;
    setState(() => _log.insert(0, '${DateTime.now().toString().substring(11, 19)}  $m'));
  }

  Future<List<String>> _ips() async =>
      (await NetworkInterface.list(type: InternetAddressType.IPv4))
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .map((a) => a.address)
          .toList();

  Future<void> _start() async {
    final port = int.tryParse(_port.text);
    if (port == null) {
      setState(() => _status = 'Porta non valida');
      return;
    }
    if (!_test && _model == null) {
      setState(() => _status = 'Scegli un modello .gguf oppure attiva la modalità test');
      return;
    }
    setState(() => _status = 'Caricamento modello…');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      final LlmEngine eng = _test ? MockEngine() : LlamaEngine();
      await eng.load(_model ?? '');
      final srv = AiServer(eng,
          systemPrompt: _system.text, apiKey: _key.text.trim(), onLog: _addLog);
      await srv.start(port);
      await WakelockPlus.enable();
      final p = await SharedPreferences.getInstance();
      await p.setString('port', _port.text);
      await p.setString('key', _key.text);
      await p.setString('system', _system.text);
      if (_model != null) await p.setString('model', _model!);
      await p.setBool('test', _test);
      final urls = (await _ips()).map((i) => 'http://$i:$port/v1').join('   ');
      setState(() {
        _server = srv;
        _running = true;
        _status = 'Attivo su $urls';
      });
    } catch (e) {
      setState(() => _status = 'Errore: $e');
    }
  }

  Future<void> _stop() async {
    await _server?.stop();
    await WakelockPlus.disable();
    setState(() {
      _server = null;
      _running = false;
      _status = 'Fermo';
    });
  }

  @override
  Widget build(BuildContext context) {
    final off = _running;
    return Scaffold(
      appBar: AppBar(title: const Text('DomyAI Server')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SelectableText(_status, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _models.contains(_model) ? _model : null,
          decoration: const InputDecoration(labelText: 'Modello (.gguf)'),
          items: _models
              .map((p) => DropdownMenuItem(value: p, child: Text(p.split('/').last, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: off ? null : (v) => setState(() => _model = v),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('Cartella modelli: $_dir', style: Theme.of(context).textTheme.bodySmall)),
          TextButton(onPressed: off ? null : () => setState(_scan), child: const Text('Aggiorna')),
        ]),
        TextField(controller: _port, enabled: !off, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Porta')),
        TextField(controller: _key, enabled: !off, decoration: const InputDecoration(labelText: 'API key (vuota = nessuna)')),
        TextField(controller: _system, enabled: !off, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Prompt di sistema')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Modalità test (senza modello)'),
          value: _test,
          onChanged: off ? null : (v) => setState(() => _test = v),
        ),
        FilledButton(onPressed: off ? _stop : _start, child: Text(off ? 'Ferma server' : 'Avvia server')),
        const SizedBox(height: 16),
        Text('Registro', style: Theme.of(context).textTheme.titleSmall),
        ..._log.take(30).map((l) => Text(l, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}
