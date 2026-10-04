import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'profile_screen.dart';

// Publishable key is public by design; RLS protects the data.
// Supplied via --dart-define-from-file=env/dev.json (see .vscode/launch.json).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

SupabaseClient get supabase => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    throw StateError('Missing config: run with --dart-define-from-file=env/dev.json');
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseKey,
    authOptions: const FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  runApp(const RideAlongApp());
}

class RideAlongApp extends StatelessWidget {
  const RideAlongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideAlong',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const AuthGate(),
    );
  }
}

/// Login screen when signed out, otherwise the profile gate.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        final user = supabase.auth.currentUser;
        if (user == null) return const LoginScreen();
        return ProfileGate(key: ValueKey(user.id));
      },
    );
  }
}

/// Keeps the auth session in Android Keystore / iOS Keychain instead of plain SharedPreferences.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _storage = FlutterSecureStorage();
  static const _key = 'supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
}

/// Server errors (RLS, RPC `raise exception`) carry a user-readable message; anything else is generic.
void showError(BuildContext context, Object error) {
  final message = switch (error) {
    AuthException(:final message) => message,
    PostgrestException(:final message) => message,
    _ when kDebugMode => 'Error: $error',
    _ => 'Something went wrong. Check your connection and try again.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
