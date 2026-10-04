import 'package:flutter/material.dart';

import 'main.dart';
import 'ui.dart';

// One query serves both roles: RLS returns all requests to the driver, only your own to a passenger,
// and the vehicle only to the driver or an accepted passenger.
const _rideDetails = '*, '
    'driver:profiles!rides_driver_id_fkey(id, name, rating_avg, rating_count), '
    'vehicle:vehicles(model, registration_number), '
    'ride_requests(id, passenger_id, seats, status, created_at, '
    'passenger:profiles!ride_requests_passenger_id_fkey(id, name, rating_avg, rating_count)), '
    'ratings(from_user, to_user)';

class RideDetailsScreen extends StatefulWidget {
  const RideDetailsScreen({super.key, required this.rideId});

  final String rideId;

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  late Future<Map<String, dynamic>> _ride = _load();
  bool _busy = false;
  int _seats = 1;

  String get _uid => supabase.auth.currentUser!.id;

  Future<Map<String, dynamic>> _load() => supabase.from('rides').select(_rideDetails).eq('id', widget.rideId).single();

  Future<void> _reload() async {
    setState(() { _ride = _load(); });
    await _ride;
  }

  /// Runs a server action, shows its error (the RPCs raise readable messages), then reloads.
  Future<void> _act(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params, {String? done}) =>
      _act(() => supabase.rpc(fn, params: params), done: done);

  Future<void> _rate(Map<String, dynamic> person) async {
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RatingSheet(name: person['name'] as String),
    );
    if (result == null) return;
    final (score, comment) = result;
    await _rpc('rate_user', {
      'p_ride_id': widget.rideId,
      'p_to_user': person['id'],
      'p_score': score,
      'p_comment': comment.isEmpty ? null : comment,
    }, done: 'Thanks for your rating');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ride,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Ride not available',
              message: 'It may have been cancelled, or check your connection.',
              action: FilledButton(onPressed: _reload, child: const Text('Retry')),
            ),
          );
        }
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        return _content(snap.data!);
      },
    );
  }

  Widget _content(Map<String, dynamic> ride) {
    final isDriver = ride['driver_id'] == _uid;
    final status = ride['status'] as String;
    final requests = (ride['ride_requests'] as List).cast<Map<String, dynamic>>()
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    final rated = {
      for (final r in (ride['ratings'] as List))
        if (r['from_user'] == _uid) r['to_user'] as String,
    };
    final myRequest = isDriver ? null : requests.where((r) => r['passenger_id'] == _uid).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(isDriver ? 'Your ride' : 'Ride details'),
        actions: [StatusChip(status), const SizedBox(width: 16)],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _TripCard(ride: ride, isDriver: isDriver),
            if (isDriver) ..._driverSections(ride, requests, rated) else ..._passengerSections(ride, myRequest, rated),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(ride, isDriver, myRequest),
    );
  }

  // ---------- Driver ----------

  List<Widget> _driverSections(Map<String, dynamic> ride, List<Map<String, dynamic>> requests, Set<String> rated) {
    final status = ride['status'] as String;
    final visible = requests.where((r) => r['status'] != 'cancelled' || status == 'scheduled').toList();
    return [
      if (ride['vehicle'] != null) ...[const SectionTitle('Your vehicle'), _VehicleCard(vehicle: ride['vehicle'])],
      SectionTitle('Requests', trailing: Text('${ride['seats_available']} seats left')),
      if (visible.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Icon(Icons.hourglass_empty_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(child: Text('No requests yet. Passengers going your way will show up here.')),
            ]),
          ),
        ),
      for (final r in visible) ...[
        _RequestTile(
          request: r,
          canRespond: status == 'scheduled' && r['status'] == 'pending' && !_busy,
          onAccept: () => _rpc('respond_request', {'p_request_id': r['id'], 'p_accept': true}, done: 'Seat confirmed'),
          onReject: () => _rpc('respond_request', {'p_request_id': r['id'], 'p_accept': false}),
          onRate: status == 'completed' && r['status'] == 'accepted' && !rated.contains(r['passenger_id'])
              ? () => _rate(r['passenger'] as Map<String, dynamic>)
              : null,
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  // ---------- Passenger ----------

  List<Widget> _passengerSections(Map<String, dynamic> ride, Map<String, dynamic>? myRequest, Set<String> rated) {
    final driver = ride['driver'] as Map<String, dynamic>;
    final reqStatus = myRequest?['status'] as String?;
    final rideStatus = ride['status'] as String;
    final (icon, title, message) = switch ((rideStatus, reqStatus)) {
      ('cancelled', _) => (Icons.cancel_rounded, 'Ride cancelled', 'The driver cancelled this ride.'),
      ('completed', 'accepted') => (Icons.check_circle_rounded, 'Trip completed', 'Hope you had a good ride.'),
      ('started', 'accepted') => (Icons.directions_car_rounded, 'On the way', 'Your driver has started the trip.'),
      (_, 'accepted') => (Icons.verified_rounded, 'Seat confirmed', 'Be at the pickup point a few minutes early.'),
      (_, 'pending') => (Icons.schedule_rounded, 'Waiting for the driver', 'You\'ll see it here once they respond.'),
      (_, 'rejected') => (Icons.block_rounded, 'Request declined', 'The driver couldn\'t take this request.'),
      (_, 'expired') => (Icons.timer_off_rounded, 'Request expired', 'The ride started before it was confirmed.'),
      _ => (null, null, null),
    };
    return [
      if (title != null) ...[
        const SizedBox(height: 12),
        _Banner(icon: icon!, title: title, message: message!, status: reqStatus ?? rideStatus),
      ],
      const SectionTitle('Driver'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Avatar(driver['name'] as String, radius: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(driver['name'] as String, style: Theme.of(context).textTheme.titleMedium),
                  RatingText(profile: driver),
                ]),
              ),
              if (rideStatus == 'completed' && reqStatus == 'accepted' && !rated.contains(driver['id']))
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _busy ? null : () => _rate(driver),
                  icon: const Icon(Icons.star_rounded),
                  label: const Text('Rate'),
                ),
            ]),
            const Divider(height: 28),
            if (ride['vehicle'] != null)
              _VehicleRow(vehicle: ride['vehicle'])
            else
              Row(children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                const Expanded(child: Text('Vehicle details appear once your seat is confirmed.')),
              ]),
          ]),
        ),
      ),
    ];
  }

  // ---------- Bottom actions ----------

  Widget? _bottomBar(Map<String, dynamic> ride, bool isDriver, Map<String, dynamic>? myRequest) {
    final status = ride['status'] as String;
    final id = ride['id'];
    final scheme = Theme.of(context).colorScheme;
    Widget bar(Widget child) => SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: child,
          ),
        );

    if (isDriver) {
      if (status == 'scheduled') {
        return bar(Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirm(context,
                          title: 'Cancel this ride?',
                          message: 'All passengers will be notified and their requests cancelled.',
                          action: 'Cancel ride')) {
                        await _rpc('update_ride_status', {'p_ride_id': id, 'p_status': 'cancelled'}, done: 'Ride cancelled');
                      }
                    },
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _rpc('update_ride_status', {'p_ride_id': id, 'p_status': 'started'}),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start ride'),
            ),
          ),
        ]));
      }
      if (status == 'started') {
        return bar(FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _rpc('update_ride_status', {'p_ride_id': id, 'p_status': 'completed'}, done: 'Ride completed'),
          icon: const Icon(Icons.flag_rounded),
          label: const Text('Complete ride'),
        ));
      }
      return null;
    }

    final reqStatus = myRequest?['status'];
    if (status != 'scheduled') return null;
    if (reqStatus == 'pending' || reqStatus == 'accepted') {
      return bar(OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
        onPressed: _busy
            ? null
            : () async {
                if (await confirm(context,
                    title: 'Cancel your request?',
                    message: reqStatus == 'accepted' ? 'Your confirmed seat will be released.' : 'The driver won\'t see it anymore.',
                    action: 'Cancel request')) {
                  await _rpc('cancel_request', {'p_request_id': myRequest!['id']}, done: 'Request cancelled');
                }
              },
        child: const Text('Cancel request'),
      ));
    }
    final available = ride['seats_available'] as int;
    if (available == 0) return null;
    final maxSeats = available < 4 ? available : 4; // DB caps a request at 4 seats
    if (_seats > maxSeats) _seats = maxSeats;
    final total = (ride['contribution_amount'] as num) * _seats;
    return bar(Row(children: [
      CountStepper(value: _seats, min: 1, max: maxSeats, onChanged: (v) => setState(() => _seats = v)),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton(
          onPressed: _busy
              ? null
              : () => _rpc('request_seat', {'p_ride_id': id, 'p_seats': _seats}, done: 'Request sent to the driver'),
          child: Text('Request · ${money(total)}'),
        ),
      ),
    ]));
  }
}

// ---------- Pieces ----------

class _TripCard extends StatelessWidget {
  const _TripCard({required this.ride, required this.isDriver});

  final Map<String, dynamic> ride;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final departure = localTime(ride['departure_time']);
    final relative = ride['status'] == 'scheduled' ? relativeDeparture(departure) : null;
    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        );
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDeparture(context, departure), style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (relative != null)
            Text(relative, style: text.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          RouteLine(from: ride['origin_text'] as String, to: ride['destination_text'] as String, large: true),
          const SizedBox(height: 20),
          Row(children: [
            stat('Per seat', money(ride['contribution_amount'] as num)),
            if (isDriver)
              stat('Booked', '${ride['seats_booked']} / ${ride['seats_total']}')
            else
              stat('Seats left', '${ride['seats_available']}'),
            if (isDriver) stat('Earning', money((ride['contribution_amount'] as num) * (ride['seats_booked'] as int))),
          ]),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.message, required this.status});

  final IconData icon;
  final String title;
  final String message;
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      'accepted' || 'completed' || 'started' => (s.primaryContainer, s.onPrimaryContainer),
      'pending' => (s.tertiaryContainer, s.onTertiaryContainer),
      'rejected' || 'cancelled' => (s.errorContainer, s.onErrorContainer),
      _ => (s.surfaceContainerHighest, s.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, color: fg, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
            Text(message, style: TextStyle(color: fg)),
          ]),
        ),
      ]),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicle});

  final Map<String, dynamic> vehicle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(Icons.directions_car_rounded, color: scheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(vehicle['model'] as String, style: Theme.of(context).textTheme.bodyLarge)),
      // Number-plate look.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.onSurface, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(vehicle['registration_number'] as String,
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: 'monospace')),
      ),
    ]);
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});

  final Map<String, dynamic> vehicle;

  @override
  Widget build(BuildContext context) =>
      Card(child: Padding(padding: const EdgeInsets.all(16), child: _VehicleRow(vehicle: vehicle)));
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.canRespond,
    required this.onAccept,
    required this.onReject,
    this.onRate,
  });

  final Map<String, dynamic> request;
  final bool canRespond;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final passenger = request['passenger'] as Map<String, dynamic>;
    final status = request['status'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Avatar(passenger['name'] as String),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(passenger['name'] as String, style: Theme.of(context).textTheme.titleSmall),
                RatingText(profile: passenger),
              ]),
            ),
            Text(plural(request['seats'] as int, 'seat'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 10),
            if (!canRespond) StatusChip(status),
          ]),
          if (canRespond) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onReject,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ]),
          ],
          if (onRate != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onRate,
                icon: const Icon(Icons.star_rounded),
                label: Text('Rate ${firstName(passenger['name'] as String)}'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet({required this.name});

  final String name;

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final _comment = TextEditingController();
  int _score = 0;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Avatar(widget.name, radius: 32),
        const SizedBox(height: 12),
        Text('How was your ride with ${firstName(widget.name)}?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 40,
              onPressed: () => setState(() => _score = i),
              icon: Icon(i <= _score ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF59E0B)),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'Add a comment (optional)'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _score == 0 ? null : () => Navigator.of(context).pop((_score, _comment.text.trim())),
            child: const Text('Submit rating'),
          ),
        ),
      ]),
    );
  }
}
