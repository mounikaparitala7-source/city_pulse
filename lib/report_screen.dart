import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'services.dart';
import 'widgets.dart';

class ReportScreen extends StatefulWidget {
  final AppUser user;
  const ReportScreen({super.key, required this.user});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _landmark = TextEditingController();
  final MapController _mc = MapController();
  String _category = categories.first.name;
  String? _photo;
  LatLng? _point;
  bool _locating = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (!_locating) setState(() => _locating = true);
    final p = await currentPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (p != null) _point = LatLng(p.latitude, p.longitude);
    });
    if (p != null) {
      try {
        _mc.move(_point!, 16);
      } catch (_) {}
    } else {
      toast(context, 'GPS unavailable. Tap the map to set the location.');
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null) {
      toast(context, 'Set the location first (GPS or tap the map).');
      return;
    }
    setState(() => _busy = true);
    try {
      // Step 1: duplicate detection.
      final dups = await findDuplicates(_category, _point!.latitude, _point!.longitude);
      if (!mounted) return;
      if (dups.isNotEmpty) {
        final choice = await _showDuplicates(dups);
        if (!mounted) return;
        if (choice == null) return; // cancelled
        if (choice != 'new') {
          final c = dups.firstWhere((d) => d.id == choice);
          if (!c.supporters.contains(widget.user.uid) && c.createdBy != widget.user.uid) {
            await toggleSupport(c, widget.user);
          }
          if (!mounted) return;
          Navigator.pop(context);
          toast(context, 'Your support was added to the existing complaint.');
          openDetail(context, c.id, widget.user);
          return;
        }
      }
      // Step 2: create, prioritise and assign.
      final c = await createComplaint(
        user: widget.user,
        title: _title.text,
        description: _description.text,
        category: _category,
        lat: _point!.latitude,
        lng: _point!.longitude,
        landmark: _landmark.text,
        photo: _photo,
      );
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Submitted. ${c.priority} priority, assigned to ${c.department}.');
    } catch (e) {
      if (mounted) toast(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showDuplicates(List<Complaint> dups) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Similar issue already reported nearby',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Support the existing complaint to raise its priority instead of creating a duplicate.'),
              const SizedBox(height: 12),
              for (final d in dups.take(3))
                Card(
                elevation: 0, color: Colors.white, shape: kCardShape,
                  child: ListTile(
                    title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${distanceMeters(_point!.latitude, _point!.longitude, d.lat, d.lng).round()} m away · '
                      '${d.status} · ${d.supporters.length} supporters',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx, d.id),
                      child: const Text('Support'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'new'),
                child: const Text('Mine is different, submit anyway'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 18),
                    label: Text(c.name),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Goes to: ${categoryOf(_category).department}',
                style: TextStyle(color: scheme.primary, fontSize: 12)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Short title'),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Enter a short title' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Describe the problem' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _landmark,
              decoration: const InputDecoration(labelText: 'Landmark (optional)'),
            ),
            const SizedBox(height: 16),
            const Text('Photo', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_photo != null) PhotoBox(_photo, height: 180),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await pickPhoto(context);
                if (p != null && mounted) setState(() => _photo = p);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_photo == null ? 'Add photo' : 'Change photo'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Location', style: TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(_locating ? 'Locating...' : 'Use GPS'),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  mapController: _mc,
                  options: MapOptions(
                    initialCenter: _point ?? defaultCenter,
                    initialZoom: 15,
                    onTap: (tapPosition, latLng) => setState(() => _point = latLng),
                  ),
                  children: [
                    TileLayer(urlTemplate: osmTiles, userAgentPackageName: osmAgent),
                    if (_point != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _point!,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on, size: 42, color: Colors.red),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _point == null
                  ? 'No location yet. Tap the map to drop the pin.'
                  : 'Pinned at ${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}. Tap the map to adjust.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Submit complaint'),
            ),
          ],
        ),
      ),
    );
  }
}
