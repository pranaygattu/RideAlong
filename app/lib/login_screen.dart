import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

/// Email OTP login. ponytail: email for dev; switch to phone OTP once an SMS provider is set up.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() => _run(() async {
        final email = _email.text.trim();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          throw const AuthException('Enter a valid email');
        }
        await supabase.auth.signInWithOtp(email: email);
        setState(() => _codeSent = true);
      });

  // On success AuthGate swaps this screen out.
  void _verify() => _run(() => supabase.auth.verifyOTP(
        email: _email.text.trim(),
        token: _code.text.trim(),
        type: OtpType.email,
      ));

  // ponytail: debug-only password login for dashboard-created test users, until custom SMTP is set up.
  // kDebugMode is const, so this is compiled out of release builds.
  final _password = TextEditingController();
  void _devPasswordLogin() => _run(() => supabase.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text('RideAlong', style: Theme.of(context).textTheme.headlineLarge),
            const Text('Find people already going your way.'),
            const SizedBox(height: 32),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'Code from email', border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: Text(_codeSent ? 'Verify' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _codeSent = false),
                child: const Text('Use a different email'),
              ),
            if (kDebugMode && !_codeSent) ...[
              const Divider(height: 48),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Test password (debug only)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _devPasswordLogin,
                child: const Text('Sign in with password (debug only)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
