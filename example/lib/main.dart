// "Acme Bank": a small app with a masked card number, a Buy button, a token
// field and Get help.
//
//   flutter run --dart-define=GAIADESK_EMBED_TOKEN=gdemb_… \
//               [--dart-define=GAIADESK_SERVER=https://…] \
//               [--dart-define=GAIADESK_DEMO_AUTOSTART=1]
//
// Every event is printed as one line (`flutter logs`). Tests drive it through
// the environment instead (demo_hooks.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

import 'demo_hooks.dart';

const _definedToken = String.fromEnvironment('GAIADESK_EMBED_TOKEN');
const _definedServer = String.fromEnvironment('GAIADESK_SERVER');
final _token = _definedToken.isNotEmpty ? _definedToken : demoEnv('GAIADESK_EMBED_TOKEN') ?? '';
final _server = _definedServer.isNotEmpty ? _definedServer : demoEnv('GAIADESK_SERVER') ?? '';
final _autostart = const bool.fromEnvironment('GAIADESK_DEMO_AUTOSTART') ||
    const String.fromEnvironment('GAIADESK_DEMO_AUTOSTART') == '1' ||
    demoFlag('GAIADESK_DEMO_AUTOSTART');
const _company = 'Acme Bank';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDemoEnv();
  runApp(const AcmeBankApp());
}

class AcmeBankApp extends StatelessWidget {
  const AcmeBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _company,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F5FBF), useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _tokenField = TextEditingController(text: _token);
  EmbedSession? _session;
  String _status = 'Not sharing';
  String? _code;
  bool _guided = demoFlag('GAIADESK_DEMO_GUIDED');
  int _bought = 0;
  final _cardKey = GlobalKey();
  final _blueKey = GlobalKey();
  final _buyKey = GlobalKey();
  Timer? _commands;

  @override
  void initState() {
    super.initState();
    _commands = watchDemoCommands(_demoCommand);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.sizeOf(context);
      demoEmit({
        'type': 'demo',
        'frame': [size.width, size.height],
        'card': demoBox(_cardKey),
        'blue': demoBox(_blueKey),
        'buy': demoBox(_buyKey),
      });
      if (_autostart && _token.isNotEmpty) _getHelp();
    });
  }

  void _demoCommand(String cmd) {
    switch (cmd) {
      case 'stop':
        _session?.stop();
      case 'pause':
        _session?.setPaused(true);
      case 'resume':
        _session?.setPaused(false);
    }
  }

  @override
  void dispose() {
    _commands?.cancel();
    _session?.stop();
    _tokenField.dispose();
    super.dispose();
  }

  Future<void> _getHelp() async {
    final token = _tokenField.text.trim();
    if (token.isEmpty) {
      setState(() => _status = 'Paste an embed token (gdemb_…) from your backend first');
      return;
    }
    // 1. Ask. 2. Start with the answer.
    final agreed = demoFlag('GAIADESK_DEMO_TEST_CONSENT') || await GaiaDeskEmbed.requestConsent(_company, guided: _guided);
    if (!agreed) {
      setState(() => _status = 'You chose not to share');
      return;
    }
    try {
      final session = await GaiaDeskEmbed.start(
        EmbedOptions(
          embedToken: token,
          company: _company,
          server: _server.isEmpty ? null : _server,
          guided: _guided,
          captureMethod: demoEnv('GAIADESK_DEMO_CAPTURE') == 'snapshot' ? IosCaptureMethod.snapshot : IosCaptureMethod.replayKit,
        ),
        consentGranted: agreed,
      );
      setState(() {
        _session = session;
        _status = 'Starting…';
      });
      session.events.listen(_onEvent);
      final reason = await session.ended;
      if (mounted) {
        setState(() {
          _session = null;
          _code = null;
          _status = 'Ended ($reason)';
        });
      }
    } on EmbedException catch (e) {
      debugPrint('gaiadesk_embed refused: ${e.code} ${e.message}');
      demoEmit({'start_error': e.code, 'message': e.message});
      setState(() => _status = 'Could not start: ${e.code}');
    }
  }

  void _onEvent(EmbedEvent e) {
    debugPrint('gaiadesk_embed event: $e');
    demoEmit(demoEventJson(e));
    setState(() {
      switch (e) {
        case EmbedState(:final state):
          _status = state;
        case EmbedCode(:final code):
          _code = code;
          _status = 'Waiting for support';
        case EmbedJoined(:final agent):
          _status = '${agent ?? 'An agent'} is viewing';
        case EmbedLeft():
          _status = 'The agent left';
        case EmbedControl(:final allowed):
          _status = allowed ? 'Guided control allowed' : 'Guided control paused';
        case EmbedAction():
        case EmbedEnded():
          break;
        case EmbedErrorEvent(:final code):
          _status = 'Problem: $code';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sharing = _session != null;
    return Scaffold(
      appBar: AppBar(title: const Text(_company)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Painted out of every frame support sees.
          GaiaDeskMasked(
            key: _cardKey,
            child: const Card(
              child: ListTile(
                leading: Icon(Icons.credit_card),
                title: Text('4111 1111 1111 1111'),
                subtitle: Text('Exp 12/29 · CVC 123'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            key: _blueKey,
            height: 64,
            alignment: Alignment.center,
            color: const Color(0xFF1F5FBF),
            child: const Text('Balance shown to support', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: _buyKey,
            onPressed: () {
              setState(() => _bought++);
              demoEmit({'bought': _bought});
            },
            child: Text(_bought == 0 ? 'Buy' : 'Bought $_bought'),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _tokenField,
            enabled: !sharing,
            decoration: const InputDecoration(labelText: 'Embed token', hintText: 'gdemb_…', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            title: const Text('Allow guided input'),
            subtitle: const Text('Only in a cobrowse session'),
            value: _guided,
            onChanged: sharing ? null : (v) => setState(() => _guided = v),
          ),
          const SizedBox(height: 8),
          if (!sharing)
            OutlinedButton.icon(onPressed: _getHelp, icon: const Icon(Icons.support_agent), label: const Text('Get help'))
          else
            OutlinedButton.icon(onPressed: () => _session?.stop(), icon: const Icon(Icons.stop), label: const Text('Stop sharing')),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center),
          if (_code != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText('Support code: $_code', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            ),
        ],
      ),
    );
  }
}
