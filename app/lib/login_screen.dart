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
  final _password = TextEditingController();
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
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _validEmail() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const AuthException('Enter a valid email');
    }
    return email;
  }

  void _sendCode() => _run(() async {
        await supabase.auth.signInWithOtp(email: _validEmail());
        setState(() => _codeSent = true);
      });

  // On success AuthGate swaps this screen out.
  void _verify() => _run(() => supabase.auth.verifyOTP(
        email: _validEmail(),
        token: _code.text.trim(),
        type: OtpType.email,
      ));

  // ponytail: debug-only password login for dashboard-created test users, until custom SMTP is set up.
  // kDebugMode is const, so this is compiled out of release builds.
  void _devPasswordLogin() => _run(() => supabase.auth.signInWithPassword(
        email: _validEmail(),
        password: _password.text,
      ));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.directions_car_filled_rounded, color: scheme.onPrimary, size: 34),
            ),
            const SizedBox(height: 28),
            Text('RideAlong', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'We sent a code to ${_email.text.trim()}. Enter it below.'
                  : 'Share rides with people already going your way.',
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 40),
            if (!_codeSent)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _sendCode(),
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              )
            else
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 10,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w600),
                onSubmitted: (_) => _busy ? null : _verify(),
                decoration: const InputDecoration(hintText: '••••••', counterText: ''),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_codeSent ? 'Verify and continue' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() => _codeSent = false),
                child: const Text('Use a different email'),
              ),
            if (kDebugMode && !_codeSent) ...[
              const SizedBox(height: 32),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('DEBUG ONLY', style: text.labelSmall?.copyWith(color: scheme.error)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Test user password', prefixIcon: Icon(Icons.key_rounded)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _devPasswordLogin,
                child: const Text('Sign in with password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
