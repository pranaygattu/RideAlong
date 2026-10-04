import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'main.dart';

/// Loads the signed-in user's profile; asks them to create one if missing.
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<Map<String, dynamic>?> _profile = _load();

  Future<Map<String, dynamic>?> _load() =>
      supabase.from('profiles').select().eq('id', supabase.auth.currentUser!.id).maybeSingle();

  void _reload() => setState(() => _profile = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profile,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load your profile.'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ]),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final profile = snap.data;
        if (profile == null) return ProfileScreen(onSaved: _reload);
        return HomeScreen(profile: profile, onProfileChanged: _reload);
      },
    );
  }
}

/// Create (existing == null) or edit the profile.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.existing, required this.onSaved});

  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.existing?['name'] as String?);
  late bool _canDrive = widget.existing?['can_drive'] as bool? ?? false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your name (max 80 characters)')));
      return;
    }
    setState(() => _busy = true);
    try {
      // Upsert so a retry after a dropped response doesn't hit a duplicate key.
      await supabase.from('profiles').upsert({
        'id': supabase.auth.currentUser!.id,
        'name': name,
        'can_drive': _canDrive,
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Create your profile' : 'Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I also drive'),
            subtitle: const Text('Lets you offer rides'),
            value: _canDrive,
            onChanged: (v) => setState(() => _canDrive = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
