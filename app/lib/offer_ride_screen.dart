import 'package:flutter/material.dart';

import 'main.dart';
import 'ui.dart';

/// Driver publishes a ride. Pops with the new ride id.
class OfferRideScreen extends StatefulWidget {
  const OfferRideScreen({super.key});

  @override
  State<OfferRideScreen> createState() => _OfferRideScreenState();
}

enum _When { now, in10, in30, custom }

class _OfferRideScreenState extends State<OfferRideScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _amount = TextEditingController(text: '50');
  late Future<List<Map<String, dynamic>>> _vehicles = _loadVehicles();
  String? _vehicleId;
  _When _when = _When.now;
  DateTime? _customTime;
  int _seats = 1;
  bool _busy = false;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadVehicles() async {
    final list = await supabase
        .from('vehicles')
        .select()
        .eq('owner_id', supabase.auth.currentUser!.id)
        .order('created_at');
    if (list.isNotEmpty && !list.any((v) => v['id'] == _vehicleId)) _vehicleId = list.last['id'] as String;
    return list;
  }

  Future<void> _addVehicle() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddVehicleSheet(),
    );
    if (id == null) return;
    setState(() {
      _vehicleId = id;
      _vehicles = _loadVehicles();
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _customTime ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customTime ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _customTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _when = _When.custom;
    });
  }

  DateTime get _departure => switch (_when) {
        _When.now => DateTime.now(),
        _When.in10 => DateTime.now().add(const Duration(minutes: 10)),
        _When.in30 => DateTime.now().add(const Duration(minutes: 30)),
        _When.custom => _customTime!,
      };

  Future<void> _publish(Map<String, dynamic> vehicle) async {
    final from = _from.text.trim(), to = _to.text.trim();
    final amount = num.tryParse(_amount.text.trim());
    // Friendly messages; the server re-checks all of this.
    if (from.isEmpty || to.isEmpty) return showMessage(context, 'Enter where you start and where you\'re going');
    if (from.length > 200 || to.length > 200) return showMessage(context, 'Keep places under 200 characters');
    if (amount == null || amount < 0 || amount > 5000) {
      return showMessage(context, 'Contribution must be between ₹0 and ₹5000');
    }
    if (_when == _When.custom && _customTime!.isBefore(DateTime.now())) {
      return showMessage(context, 'Pick a time in the future');
    }

    setState(() => _busy = true);
    try {
      final id = await supabase.rpc('create_ride', params: {
        'p_vehicle_id': vehicle['id'],
        'p_origin': from,
        'p_destination': to,
        'p_departure': _departure.toUtc().toIso8601String(),
        'p_seats': _seats,
        'p_contribution': amount,
      });
      if (mounted) Navigator.of(context).pop(id as String);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offer a ride')),
      body: FutureBuilder(
        future: _vehicles,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Couldn\'t load your vehicles',
              message: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => setState(() { _vehicles = _loadVehicles(); }),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final vehicles = snap.data!;
          if (vehicles.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.directions_car_rounded,
                title: 'Add your vehicle first',
                message: 'Passengers see your vehicle once you confirm their seat.',
                action: FilledButton.icon(
                  onPressed: _addVehicle,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add vehicle'),
                ),
              ),
            );
          }
          final vehicle = vehicles.firstWhere((v) => v['id'] == _vehicleId, orElse: () => vehicles.last);
          final capacity = vehicle['seat_capacity'] as int;
          if (_seats > capacity) _seats = capacity;
          return _form(vehicles, vehicle, capacity);
        },
      ),
    );
  }

  Widget _form(List<Map<String, dynamic>> vehicles, Map<String, dynamic> vehicle, int capacity) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final amount = num.tryParse(_amount.text.trim());
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const SectionTitle('Route'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(children: [
                      TextField(
                        controller: _from,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          hintText: 'Starting from',
                          prefixIcon: Icon(Icons.trip_origin_rounded, color: scheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _to,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Going to',
                          prefixIcon: Icon(Icons.location_on_rounded, color: scheme.primary),
                        ),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Swap',
                    onPressed: () {
                      final t = _from.text;
                      _from.text = _to.text;
                      _to.text = t;
                    },
                    icon: const Icon(Icons.swap_vert_rounded),
                  ),
                ]),
              ),
            ),
            const SectionTitle('Leaving'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (option, label) in [(_When.now, 'Now'), (_When.in10, 'In 10 min'), (_When.in30, 'In 30 min')])
                ChoiceChip(
                  label: Text(label),
                  selected: _when == option,
                  onSelected: (_) => setState(() => _when = option),
                ),
              ChoiceChip(
                avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(_customTime == null ? 'Pick time' : formatDeparture(context, _customTime!)),
                selected: _when == _When.custom,
                onSelected: (_) => _pickTime(),
              ),
            ]),
            const SectionTitle('Vehicle'),
            Card(
              child: RadioGroup<String>(
                groupValue: vehicle['id'] as String,
                onChanged: (id) => setState(() => _vehicleId = id),
                child: Column(children: [
                  for (final v in vehicles)
                    RadioListTile<String>(
                      value: v['id'] as String,
                      title: Text(v['model'] as String),
                      subtitle: Text('${v['registration_number']}  ·  ${plural(v['seat_capacity'] as int, 'seat')}'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Add another vehicle'),
                    onTap: _addVehicle,
                  ),
                ]),
              ),
            ),
            const SectionTitle('Seats offered'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(Icons.event_seat_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Up to $capacity in this vehicle', style: text.bodyMedium)),
                  CountStepper(value: _seats, min: 1, max: capacity, onChanged: (v) => setState(() => _seats = v)),
                ]),
              ),
            ),
            const SectionTitle('Contribution per seat'),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: text.titleLarge,
              decoration: const InputDecoration(
                prefixText: '₹ ',
                helperText: 'A share of fuel and tolls — not a fare.',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final v in [30, 50, 80, 100])
                ActionChip(
                  label: Text(money(v)),
                  onPressed: () => setState(() => _amount.text = '$v'),
                ),
            ]),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('You could receive', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(amount == null ? '—' : money(amount * _seats),
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => _publish(vehicle),
                child: const Text('Publish ride'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet();

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _model = TextEditingController();
  final _reg = TextEditingController();
  int _seats = 3;
  bool _busy = false;

  @override
  void dispose() {
    _model.dispose();
    _reg.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final model = _model.text.trim();
    final reg = _reg.text.trim().toUpperCase();
    if (model.isEmpty || model.length > 60) return showMessage(context, 'Enter the vehicle model');
    // Mirrors the DB check constraint.
    if (!RegExp(r'^[A-Z0-9 -]{4,15}$').hasMatch(reg)) {
      return showMessage(context, 'Registration: 4–15 letters, numbers, spaces or dashes');
    }
    setState(() => _busy = true);
    try {
      final row = await supabase
          .from('vehicles')
          .insert({'model': model, 'registration_number': reg, 'seat_capacity': _seats})
          .select('id')
          .single();
      if (mounted) Navigator.of(context).pop(row['id'] as String);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add vehicle', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
          controller: _model,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Model', hintText: 'e.g. Maruti Swift, white'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reg,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Registration number', hintText: 'TS 09 AB 1234'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('Passenger seats')),
          CountStepper(value: _seats, min: 1, max: 7, onChanged: (v) => setState(() => _seats = v)),
        ]),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save vehicle')),
      ]),
    );
  }
}
