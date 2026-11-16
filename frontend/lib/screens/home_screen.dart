import 'package:flutter/material.dart';
import '../identity_service.dart';
import 'auth_screen.dart';
import 'enroll_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AuthPolicy policy = AuthPolicy.either;

  static const _activity = [
    (Icons.arrow_downward, 'Payment received', 'Northwind Ltd', '+\$2,400.00'),
    (Icons.shopping_bag_outlined, 'Card purchase', 'Harbor Market', '-\$86.40'),
    (Icons.bolt, 'Utilities', 'CityGrid Energy', '-\$132.15'),
    (Icons.arrow_upward, 'Transfer', 'Savings vault', '-\$500.00'),
  ];

  @override
  void initState() {
    super.initState();
    AccessSettings.policy().then((p) => mounted ? setState(() => policy = p) : null);
  }

  void _signOut() => Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));

  Future<void> _resetProfile() async {
    await AccessSettings.resetProfile();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EnrollScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaultline'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(tooltip: 'Reset profile', icon: const Icon(Icons.restart_alt), onPressed: _resetProfile),
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [scheme.primary.withValues(alpha: 0.85), const Color(0xFF0F3D6B)]),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total balance', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 6),
            Text('\$48,230.12', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('+2.4% this month', style: TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 20),
        Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final a in _activity)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(a.$1)),
              title: Text(a.$2),
              subtitle: Text(a.$3),
              trailing: Text(a.$4,
                  style: TextStyle(color: a.$4.startsWith('+') ? Colors.greenAccent : Colors.white70)),
            ),
          ),
        const SizedBox(height: 20),
        Text('Security', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sign-in requirement'),
              const SizedBox(height: 10),
              SegmentedButton<AuthPolicy>(
                segments: const [
                  ButtonSegment(value: AuthPolicy.either, label: Text('Face or voice')),
                  ButtonSegment(value: AuthPolicy.both, label: Text('Face and voice')),
                ],
                selected: {policy},
                onSelectionChanged: (s) {
                  setState(() => policy = s.first);
                  AccessSettings.setPolicy(s.first);
                },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const EnrollScreen())),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add or update face and voice'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
