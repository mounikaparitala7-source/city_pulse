import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'services.dart';
import 'widgets.dart';

class DetailScreen extends StatelessWidget {
  final String complaintId;
  final AppUser user;
  const DetailScreen({super.key, required this.complaintId, required this.user});

  bool _canManage(Complaint c) => user.isAdmin || (user.isOfficer && user.department == c.department);

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) toast(context, done);
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e');
    }
  }

  Future<void> _askNote(BuildContext context, Complaint c, String status, {bool withPhoto = false}) async {
    final note = TextEditingController();
    String? photo;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Mark as $status', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: withPhoto ? 'Resolution note' : 'Note for the citizen',
                ),
              ),
              if (withPhoto) ...[
                const SizedBox(height: 12),
                if (photo != null) PhotoBox(photo, height: 150),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await pickPhoto(ctx);
                    if (p != null) setSheet(() => photo = p);
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(photo == null ? 'Add resolution photo' : 'Change photo'),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      () => updateStatus(c, status, user, note: note.text.trim(), resolutionPhoto: photo),
      'Marked $status. Citizen notified.',
    );
  }

  Future<void> _reassign(BuildContext context, Complaint c) async {
    final officers = (await allUsersStream().first).where((u) => u.isOfficer).toList();
    if (!context.mounted) return;
    String dept = c.department;
    String? officerId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final inDept = officers.where((o) => o.department == dept).toList();
          return AlertDialog(
            title: const Text('Assign complaint'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: dept,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [for (final d in departments) DropdownMenuItem(value: d, child: Text(d))],
                  onChanged: (v) => setDialog(() {
                    dept = v ?? dept;
                    officerId = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey(dept),
                  value: officerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Officer'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Any officer in department')),
                    for (final o in inDept) DropdownMenuItem<String?>(value: o.uid, child: Text(o.name)),
                  ],
                  onChanged: (v) => setDialog(() => officerId = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign')),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    AppUser? officer;
    for (final o in officers) {
      if (o.uid == officerId) officer = o;
    }
    await _run(context, () => reassign(c, dept, officer, user), 'Complaint assigned.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint')),
      body: StreamBuilder<Complaint?>(
        stream: complaintStream(complaintId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final c = snap.data;
          if (c == null) return const Center(child: Text('Complaint not found'));
          final supported = c.supporters.contains(user.uid);
          final point = LatLng(c.lat, c.lng);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (c.photo != null && c.photo!.isNotEmpty) ...[
                PhotoBox(c.photo, height: 220),
                const SizedBox(height: 12),
              ],
              Text(c.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(c.status, statusColor(c.status)),
                  Pill('${c.priority} priority · score ${c.score}', priorityColor(c.priority)),
                  Pill(c.category, Colors.teal),
                ],
              ),
              const SizedBox(height: 12),
              Text(c.description),
              const SizedBox(height: 12),
              _meta(Icons.apartment, 'Department', c.department),
              _meta(Icons.badge_outlined, 'Officer', c.officerName ?? 'Not yet picked up'),
              _meta(Icons.person_outline, 'Reported by', c.createdByName),
              _meta(Icons.schedule, 'Reported on', fmtDate(c.createdAt)),
              if (c.landmark.isNotEmpty) _meta(Icons.place_outlined, 'Landmark', c.landmark),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 170,
                  child: IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(initialCenter: point, initialZoom: 16),
                      children: [
                        TileLayer(urlTemplate: osmTiles, userAgentPackageName: osmAgent),
                        MarkerLayer(markers: [
                          Marker(
                            point: point,
                            width: 44,
                            height: 44,
                            child: Icon(Icons.location_on, size: 42, color: statusColor(c.status)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Citizen support (upvote instead of duplicate).
              if (user.isCitizen && c.createdBy != user.uid && c.isOpen)
                FilledButton.tonalIcon(
                  onPressed: () => _run(
                    context,
                    () => toggleSupport(c, user),
                    supported ? 'Support removed.' : 'Thanks. Your support raises the priority.',
                  ),
                  icon: Icon(supported ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined),
                  label: Text(supported
                      ? 'You support this (${c.supporters.length})'
                      : 'I face this too (${c.supporters.length})'),
                )
              else
                Text('${c.supporters.length} citizens support this complaint',
                    style: TextStyle(color: Colors.grey.shade700)),

              // Officer / admin actions.
              if (_canManage(c)) ...[
                const Divider(height: 32),
                const Text('Manage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (c.status == 'Assigned')
                      FilledButton.icon(
                        onPressed: () => _run(
                          context,
                          () => updateStatus(c, 'In Progress', user,
                              note: 'Work started by ${user.name}', takeOwnership: true),
                          'Marked In Progress. Citizen notified.',
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start work'),
                      ),
                    if (c.isOpen)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: () => _askNote(context, c, 'Resolved', withPhoto: true),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Resolve'),
                      ),
                    if (c.isOpen)
                      OutlinedButton.icon(
                        onPressed: () => _askNote(context, c, 'Rejected'),
                        icon: const Icon(Icons.block),
                        label: const Text('Reject'),
                      ),
                    if (user.isAdmin)
                      OutlinedButton.icon(
                        onPressed: () => _reassign(context, c),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Assign department'),
                      ),
                  ],
                ),
              ],

              if (c.status == 'Resolved') ...[
                const Divider(height: 32),
                const Text('Resolution', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                if (c.resolutionNote.isNotEmpty) Text(c.resolutionNote),
                if (c.resolutionPhoto != null && c.resolutionPhoto!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PhotoBox(c.resolutionPhoto, height: 200),
                ],
                const SizedBox(height: 12),
                if (c.rating > 0)
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Icon(i <= c.rating ? Icons.star : Icons.star_border, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text('Citizen rating'),
                    ],
                  )
                else if (user.uid == c.createdBy) ...[
                  const Text('Is it really fixed? Rate the work:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          icon: const Icon(Icons.star_border, color: Colors.amber, size: 32),
                          onPressed: () => _run(context, () => rateComplaint(c, user, i), 'Thanks for your feedback.'),
                        ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _run(context, () => reopenComplaint(c, user), 'Complaint reopened.'),
                    icon: const Icon(Icons.replay),
                    label: const Text('Not fixed, reopen it'),
                  ),
                ],
              ],

              const Divider(height: 32),
              Text('Comments (${c.comments.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              for (final m in c.comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text(m.by.isEmpty ? '?' : m.by[0].toUpperCase(), style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${m.by} (${m.status}) · ${timeAgo(m.at)}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              Text(m.note),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              CommentBox(key: const ValueKey('comment-box'), complaint: c, user: user),
              const Divider(height: 32),
              const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              for (final h in c.history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.circle, size: 12, color: statusColor(h.status)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.status, style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (h.note.isNotEmpty) Text(h.note),
                            Text('${h.by} · ${fmtDate(h.at)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _meta(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey.shade700)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class CommentBox extends StatefulWidget {
  final Complaint complaint;
  final AppUser user;
  const CommentBox({super.key, required this.complaint, required this.user});

  @override
  State<CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends State<CommentBox> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await addComment(widget.complaint, widget.user, value);
      _text.clear();
    } catch (e) {
      if (mounted) toast(context, 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            decoration: const InputDecoration(hintText: 'Add a comment', isDense: true),
            onSubmitted: (_) => _send(),
          ),
        ),
        IconButton(onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
      ],
    );
  }
}
