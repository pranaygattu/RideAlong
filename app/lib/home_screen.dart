import 'package:flutter/material.dart';

import 'main.dart';
import 'profile_screen.dart';

// ponytail: placeholder; Offer Ride / Find Ride land here in the next steps.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.profile, required this.onProfileChanged});

  final Map<String, dynamic> profile;
  final VoidCallback onProfileChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RideAlong'),
        actions: [
          IconButton(
            tooltip: 'Edit profile',
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProfileScreen(
                existing: profile,
                onSaved: () {
                  Navigator.of(context).pop();
                  onProfileChanged();
                },
              ),
            )),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Center(child: Text('Hi ${profile['name']}')),
    );
  }
}
