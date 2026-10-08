// "Acme Bank": a small app with a masked card number, a Buy button, a token
// field and Get help.
//
//   flutter run --dart-define=GAIADESK_EMBED_TOKEN=gdemb_… \
//               [--dart-define=GAIADESK_SERVER=https://…] \
//               [--dart-define=GAIADESK_DEMO_AUTOSTART=1]
//
// Every event is printed as one line (`flutter logs`).
import 'package:flutter/material.dart';
import 'package:gaiadesk_embed/gaiadesk_embed.dart';

const _token = String.fromEnvironment('GAIADESK_EMBED_TOKEN');
const _server = String.fromEnvironment('GAIADESK_SERVER');
const _autostart = bool.fromEnvironment('GAIADESK_DEMO_AUTOSTART') || String.fromEnvironment('GAIADESK_DEMO_AUTOSTART') == '1';
const _company = 'Acme Bank';

void main() => runApp(const AcmeBankApp());

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
  bool _guided = false;
  int _bought = 0;

  @override
  void initState() {
    super.initState();
    if (_autostart && _token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _getHelp());
    }
  }

  @override
  void dispose() {
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
    final agreed = await GaiaDeskEmbed.requestConsent(_company, guided: _guided);
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
      setState(() => _status = 'Could not start: ${e.code}');
    }
  }

  void _onEvent(EmbedEvent e) {
    debugPrint('gaiadesk_embed event: $e');
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
          const GaiaDeskMasked(
            child: Card(
              child: ListTile(
                leading: Icon(Icons.credit_card),
                title: Text('4111 1111 1111 1111'),
                subtitle: Text('Exp 12/29 · CVC 123'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() => _bought++),
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
