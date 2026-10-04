import 'package:flutter/material.dart';

import 'main.dart';
import 'offer_ride_screen.dart';
import 'profile_screen.dart';
import 'ride_details_screen.dart';
import 'ui.dart';

const _rideWithDriver = '*, driver:profiles!rides_driver_id_fkey(id, name, rating_avg, rating_count)';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile, required this.onProfileChanged});

  final Map<String, dynamic> profile;
  final VoidCallback onProfileChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _refresh = 0; // bump to reload both tabs after returning from another screen

  bool get _canDrive => widget.profile['can_drive'] as bool;

  Future<void> _openRide(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RideDetailsScreen(rideId: id)));
    if (mounted) setState(() => _refresh++);
  }

  Future<void> _offerRide() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const OfferRideScreen()));
    if (!mounted || id == null) return;
    setState(() => _tab = 1);
    await _openRide(id);
  }

  void _openProfile() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          existing: widget.profile,
          onSaved: () {
            Navigator.of(context).pop();
            widget.onProfileChanged();
          },
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.profile['name'] as String;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, ${firstName(name)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            _tab == 0 ? 'Where are you headed?' : 'Your rides and requests',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(customBorder: const CircleBorder(), onTap: _openProfile, child: Avatar(name)),
          ),
        ],
      ),
      body: _tab == 0
          ? _FindTab(key: ValueKey('find$_refresh'), onOpen: _openRide)
          : _TripsTab(key: ValueKey('trips$_refresh'), onOpen: _openRide, onOffer: _canDrive ? _offerRide : null),
      floatingActionButton: _canDrive
          ? FloatingActionButton.extended(
              onPressed: _offerRide,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Offer a ride'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Find a ride'),
          NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon: Icon(Icons.confirmation_number_rounded),
              label: 'My trips'),
        ],
      ),
    );
  }
}

/// Shared list scaffolding: pull-to-refresh, loading, error and empty states.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({required this.future, required this.onRefresh, required this.builder, this.header});

  final Future<T> future;
  final Future<void> Function() onRefresh;
  final List<Widget> Function(T data) builder;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: FutureBuilder<T>(
        future: future,
        builder: (context, snap) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            ?header,
            if (snap.hasError)
              EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Couldn\'t load',
                message: 'Pull down to try again.',
              )
            else if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else
              ...builder(snap.data as T),
          ],
        ),
      ),
    );
  }
}

class _FindTab extends StatefulWidget {
  const _FindTab({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  State<_FindTab> createState() => _FindTabState();
}

class _FindTabState extends State<_FindTab> {
  late Future<List<Map<String, dynamic>>> _rides = _load();
  String _query = '';

  // RLS returns only *my* requests in the embedded ride_requests, so it doubles as "already requested".
  Future<List<Map<String, dynamic>>> _load() => supabase
      .from('rides')
      .select('$_rideWithDriver, ride_requests(status)')
      .eq('status', 'scheduled')
      .neq('driver_id', supabase.auth.currentUser!.id)
      .gt('seats_available', 0)
      .gt('departure_time', DateTime.now().subtract(const Duration(minutes: 15)).toUtc().toIso8601String())
      .order('departure_time')
      .limit(100);

  Future<void> _refresh() async {
    setState(() { _rides = _load(); });
    await _rides;
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      future: _rides,
      onRefresh: _refresh,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: const InputDecoration(
            hintText: 'Search by area, e.g. Hitech City',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
      builder: (rides) {
        final shown = rides.where((r) =>
            _query.isEmpty ||
            (r['origin_text'] as String).toLowerCase().contains(_query) ||
            (r['destination_text'] as String).toLowerCase().contains(_query));
        if (shown.isEmpty) {
          return [
            EmptyState(
              icon: Icons.directions_car_outlined,
              title: _query.isEmpty ? 'No rides right now' : 'No rides match "$_query"',
              message: 'When drivers going your way post a ride, it will show up here.',
            ),
          ];
        }
        return [
          for (final ride in shown) ...[
            RideCard(
              ride: ride,
              onTap: () => widget.onOpen(ride['id'] as String),
              badge: _activeRequestBadge(ride),
            ),
            const SizedBox(height: 12),
          ],
        ];
      },
    );
  }

  Widget? _activeRequestBadge(Map<String, dynamic> ride) {
    final statuses = (ride['ride_requests'] as List).map((r) => r['status'] as String);
    if (statuses.contains('accepted')) return const StatusChip('accepted');
    if (statuses.contains('pending')) return const StatusChip('pending');
    return null;
  }
}

typedef _Trip = ({Map<String, dynamic> ride, bool driving, String? requestStatus});

class _TripsTab extends StatefulWidget {
  const _TripsTab({super.key, required this.onOpen, this.onOffer});

  final ValueChanged<String> onOpen;
  final VoidCallback? onOffer;

  @override
  State<_TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<_TripsTab> {
  late Future<List<_Trip>> _trips = _load();

  Future<List<_Trip>> _load() async {
    final uid = supabase.auth.currentUser!.id;
    final (driving, requests) = await (
      supabase
          .from('rides')
          .select('*, ride_requests(status)')
          .eq('driver_id', uid)
          .order('departure_time', ascending: false)
          .limit(50),
      supabase
          .from('ride_requests')
          .select('status, ride:rides($_rideWithDriver)')
          .eq('passenger_id', uid)
          .order('created_at', ascending: false)
          .limit(50),
    ).wait;

    final trips = <_Trip>[for (final r in driving) (ride: r, driving: true, requestStatus: null)];
    final seen = <String>{};
    for (final q in requests) {
      final ride = q['ride'] as Map<String, dynamic>?;
      // Newest request per ride wins (a passenger may cancel and request again).
      if (ride != null && seen.add(ride['id'] as String)) {
        trips.add((ride: ride, driving: false, requestStatus: q['status'] as String));
      }
    }
    return trips;
  }

  Future<void> _refresh() async {
    setState(() { _trips = _load(); });
    await _trips;
  }

  static bool _isUpcoming(_Trip t) =>
      ['scheduled', 'started'].contains(t.ride['status']) &&
      (t.driving || ['pending', 'accepted'].contains(t.requestStatus));

  Widget _badge(_Trip t) {
    final rideStatus = t.ride['status'] as String;
    if (t.driving) {
      final pending = (t.ride['ride_requests'] as List).where((r) => r['status'] == 'pending').length;
      if (pending > 0 && rideStatus == 'scheduled') return StatusChip('new', label: plural(pending, 'request'));
      return StatusChip(rideStatus, label: rideStatus == 'scheduled' ? 'Driving' : null);
    }
    if (rideStatus != 'scheduled' && t.requestStatus == 'accepted') return StatusChip(rideStatus);
    return StatusChip(t.requestStatus!);
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList(
      future: _trips,
      onRefresh: _refresh,
      builder: (trips) {
        if (trips.isEmpty) {
          return [
            EmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'No trips yet',
              message: widget.onOffer != null
                  ? 'Offer a ride on your commute, or request a seat from the Find tab.'
                  : 'Request a seat from the Find tab and it will show up here.',
              action: widget.onOffer == null
                  ? null
                  : FilledButton.icon(
                      onPressed: widget.onOffer,
                      icon: const Icon(Icons.add_road_rounded),
                      label: const Text('Offer a ride'),
                    ),
            ),
          ];
        }
        DateTime dep(_Trip t) => DateTime.parse(t.ride['departure_time'] as String);
        final upcoming = trips.where(_isUpcoming).toList()..sort((a, b) => dep(a).compareTo(dep(b)));
        final past = trips.where((t) => !_isUpcoming(t)).toList()..sort((a, b) => dep(b).compareTo(dep(a)));
        Widget card(_Trip t) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RideCard(
                ride: t.ride,
                driving: t.driving,
                badge: _badge(t),
                onTap: () => widget.onOpen(t.ride['id'] as String),
              ),
            );
        return [
          if (upcoming.isNotEmpty) ...[const SectionTitle('Upcoming'), ...upcoming.map(card)],
          if (past.isNotEmpty) ...[const SectionTitle('Past'), ...past.map(card)],
        ];
      },
    );
  }
}
