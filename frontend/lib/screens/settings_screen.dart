import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _testing = false;
  String? _testResult;
  bool? _testSuccess;

  static String _defaultUrl() {
    if (Platform.isAndroid) return 'http://10.0.2.2:8001/api/auth';
    return 'http://127.0.0.1:8001/api/auth';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('backend_url') ?? '';
    _controller.text = saved.isNotEmpty ? saved : _defaultUrl();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend URL saved.')),
    );
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backend_url');
    _controller.text = _defaultUrl();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to default URL.')),
    );
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      // Strip /api/auth suffix to hit /health
      String healthUrl = url;
      if (healthUrl.endsWith('/api/auth')) {
        healthUrl = healthUrl.replaceAll('/api/auth', '');
      }
      healthUrl = '$healthUrl/health'.replaceAll('//health', '/health');

      final uri = Uri.parse(healthUrl);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final ok = resp.statusCode == 200;
      client.close();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = ok;
        _testResult = ok
            ? 'Connected! Backend is reachable ✓'
            : 'Got HTTP ${resp.statusCode} — backend might be misconfigured.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = 'Cannot reach backend: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Backend URL', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Enter the IP address of the machine running the Flask backend.\n'
            'Example: http://192.168.1.42:8001/api/auth',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'http://192.168.x.x:8001/api/auth',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _controller.clear(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: (_testSuccess == true)
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.red.withValues(alpha: 0.15),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testSuccess == true ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restore),
            title: const Text('Reset to default'),
            subtitle: const Text('Use emulator default (10.0.2.2) or localhost'),
            onTap: _reset,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: scheme.primary.withValues(alpha: 0.08),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💡 How to find your IP', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  '• On Linux/Mac: run  hostname -I  in a terminal\n'
                  '• On Windows: run  ipconfig  and look for IPv4\n'
                  '• Phone and laptop must be on the same Wi-Fi\n'
                  '• Make sure the Flask backend is running on port 8001',
                  style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
