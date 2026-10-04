import 'package:flutter/material.dart';

/// Shared look: theme, formatting helpers and small widgets used across screens.

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: brightness);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 54), shape: rounded, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 54), shape: rounded, textStyle: buttonText),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  );
}

// ---------- Formatting ----------

String money(num v) => '₹${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(2)}';

DateTime localTime(Object iso) => DateTime.parse(iso as String).toLocal();

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

String firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

/// "Today · 8:30 AM", "Tomorrow · 6:00 PM", "Sat, Oct 12 · 9:15 AM".
String formatDeparture(BuildContext context, DateTime t) {
  final l = MaterialLocalizations.of(context);
  final days = DateUtils.dateOnly(t).difference(DateUtils.dateOnly(DateTime.now())).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => l.formatMediumDate(t),
  };
  return '$day · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
}

/// "Leaving now", "in 25 min", "in 2 h 10 min"; null when further out or past.
String? relativeDeparture(DateTime t) {
  final m = t.difference(DateTime.now()).inMinutes;
  if (m < -15 || m >= 12 * 60) return null;
  if (m <= 1) return 'Leaving now';
  if (m < 60) return 'in $m min';
  return 'in ${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}';
}

// ---------- Widgets ----------

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(initials.toUpperCase(), style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600)),
    );
  }
}

class RatingText extends StatelessWidget {
  const RatingText({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final count = profile['rating_count'] as int? ?? 0;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (count == 0) return Text('New member', style: style);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
      const SizedBox(width: 2),
      Text('${(profile['rating_avg'] as num).toStringAsFixed(1)}  ·  ${plural(count, 'rating')}', style: style),
    ]);
  }
}

/// Origin → destination with a connecting line.
class RouteLine extends StatelessWidget {
  const RouteLine({super.key, required this.from, required this.to, this.large = false});

  final String from;
  final String to;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = large ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyLarge;
    Widget dot(bool filled) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? scheme.primary : scheme.surface,
            border: Border.all(color: scheme.primary, width: 3),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(children: [
            dot(false),
            Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: scheme.outlineVariant)),
            dot(true),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(from, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
            SizedBox(height: large ? 20 : 12),
            Text(to, style: style?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});

  final String status;
  final String? label;

  static const _labels = {
    'scheduled': 'Upcoming',
    'started': 'On the way',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
    'pending': 'Requested',
    'accepted': 'Confirmed',
    'rejected': 'Declined',
    'expired': 'Expired',
    'new': 'New requests',
  };

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      'accepted' || 'scheduled' => (s.primaryContainer, s.onPrimaryContainer),
      'pending' || 'started' || 'new' => (s.tertiaryContainer, s.onTertiaryContainer),
      'rejected' || 'cancelled' => (s.errorContainer, s.onErrorContainer),
      _ => (s.surfaceContainerHighest, s.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label ?? _labels[status] ?? status,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle),
          child: Icon(icon, size: 36, color: scheme.primary),
        ),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Ride summary used in lists. [driving] swaps the driver row for booking progress.
class RideCard extends StatelessWidget {
  const RideCard({super.key, required this.ride, required this.onTap, this.badge, this.driving = false});

  final Map<String, dynamic> ride;
  final VoidCallback onTap;
  final Widget? badge;
  final bool driving;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final departure = localTime(ride['departure_time']);
    final relative = ride['status'] == 'scheduled' ? relativeDeparture(departure) : null;
    final driver = ride['driver'] as Map<String, dynamic>?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.schedule_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(formatDeparture(context, departure),
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (badge != null)
                badge!
              else if (relative != null)
                Text(relative, style: text.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 14),
            RouteLine(from: ride['origin_text'] as String, to: ride['destination_text'] as String),
            Divider(height: 28, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            Row(children: [
              if (driving) ...[
                Icon(Icons.event_seat_rounded, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${ride['seats_booked']} of ${ride['seats_total']} seats booked', style: text.bodyMedium),
                ),
              ] else ...[
                Avatar(driver?['name'] as String? ?? '?', radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driver?['name'] as String? ?? 'Driver',
                        style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (driver != null) RatingText(profile: driver),
                  ]),
                ),
                Text(plural(ride['seats_available'] as int, 'seat'), style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: 12),
              ],
              Text(money(ride['contribution_amount'] as num),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
              Text(' /seat', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Pill-shaped − n + control.
class CountStepper extends StatelessWidget {
  const CountStepper({super.key, required this.value, required this.min, required this.max, required this.onChanged});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.filledTonal(
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
        width: 44,
        child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      ),
      IconButton.filledTonal(
        onPressed: value < max ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
