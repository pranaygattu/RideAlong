import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'main.dart';
import 'ui.dart';

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

  void _reload() => setState(() { _profile = _load(); });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profile,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load your profile',
                message: 'Check your connection and try again.',
                action: FilledButton(onPressed: _reload, child: const Text('Retry')),
              ),
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

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      showMessage(context, 'Enter your name (max 80 characters)');
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Welcome' : 'Your profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ListenableBuilder(
              listenable: _name,
              builder: (context, _) => Avatar(_name.text.isEmpty ? '?' : _name.text, radius: 44),
            ),
          ),
          const SizedBox(height: 12),
          if (_isNew)
            Text('Tell us your name so drivers and passengers know who they\'re riding with.',
                textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else
            Center(child: RatingText(profile: widget.existing!)),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              secondary: Icon(Icons.directions_car_rounded, color: scheme.primary),
              title: const Text('I also drive'),
              subtitle: const Text('Offer empty seats on trips you already make'),
              value: _canDrive,
              onChanged: (v) => setState(() => _canDrive = v),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_isNew ? 'Get started' : 'Save changes'),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await supabase.auth.signOut();
              },
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}
