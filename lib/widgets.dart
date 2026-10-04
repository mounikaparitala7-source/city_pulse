import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'detail_screen.dart';
import 'models.dart';
import 'services.dart';

const LatLng defaultCenter = LatLng(17.3850, 78.4867); // Hyderabad
const String osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String osmAgent = 'com.example.citypulse';

Color statusColor(String s) {
  switch (s) {
    case 'Assigned':
      return Colors.blue;
    case 'In Progress':
      return Colors.orange;
    case 'Resolved':
      return Colors.green;
    case 'Rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

Color priorityColor(String p) =>
    p == 'High' ? Colors.red : (p == 'Medium' ? Colors.deepOrange : Colors.blueGrey);

void openDetail(BuildContext context, String complaintId, AppUser user) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DetailScreen(complaintId: complaintId, user: user)),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class PhotoBox extends StatelessWidget {
  final String? data;
  final double height;
  const PhotoBox(this.data, {super.key, this.height = 200});

  @override
  Widget build(BuildContext context) {
    if (data == null || data!.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        photoBytes(data!),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

/// Lets the user take or choose a photo; returns it compressed as base64.
Future<String?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 640, imageQuality: 45);
    if (x == null) return null;
    return base64Encode(await x.readAsBytes());
  } catch (_) {
    return null;
  }
}

class ComplaintCard extends StatelessWidget {
  final Complaint c;
  final AppUser user;
  const ComplaintCard({super.key, required this.c, required this.user});

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(c.category);
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = c.photo != null && c.photo!.isNotEmpty;
    final supported = c.supporters.contains(user.uid);
    final canSupport = user.isCitizen && c.createdBy != user.uid && c.isOpen;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: kCardShape,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDetail(context, c.id, user),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                if (hasPhoto)
                  Image.memory(
                    photoBytes(c.photo!),
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else
                  Container(
                    height: 84,
                    width: double.infinity,
                    color: const Color(0xFFE5E5EA),
                    child: Icon(cat.icon, color: const Color(0xFF3A3A3C), size: 40),
                  ),
                Positioned(top: 10, left: 10, child: _tag(c.status, statusColor(c.status))),
                Positioned(top: 10, right: 10, child: _tag('${c.priority} priority', priorityColor(c.priority))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(cat.icon, size: 15, color: scheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('${c.category} · ${c.department}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 14, 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: canSupport ? () => toggleSupport(c, user) : null,
                    icon: Icon(supported ? Icons.favorite : Icons.favorite_border,
                        size: 18, color: supported ? Colors.pink : null),
                    label: Text('${c.supporters.length} me too'),
                  ),
                  TextButton.icon(
                    onPressed: () => openDetail(context, c.id, user),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text('${c.comments.length}'),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      slaText(c).isEmpty ? timeAgo(c.createdAt) : '${timeAgo(c.createdAt)} · ${slaText(c)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: slaText(c) == 'Overdue' ? Colors.red : Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: slaText(c) == 'Overdue' ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live list of complaints with a filter and optional priority ordering.
class ComplaintList extends StatelessWidget {
  final AppUser user;
  final bool Function(Complaint) filter;
  final bool byPriority;
  final String emptyText;
  const ComplaintList({
    super.key,
    required this.user,
    required this.filter,
    this.byPriority = false,
    this.emptyText = 'Nothing here yet',
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Complaint>>(
      stream: complaintsStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!.where(filter).toList();
        if (byPriority) list.sort((a, b) => b.score.compareTo(a.score));
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(emptyText, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 90),
          itemCount: list.length,
          itemBuilder: (context, i) => ComplaintCard(c: list[i], user: user),
        );
      },
    );
  }
}

/// Interactive map of complaints. Pins are coloured by status.
class ComplaintsMap extends StatefulWidget {
  final AppUser user;
  final bool Function(Complaint) filter;
  const ComplaintsMap({super.key, required this.user, required this.filter});

  @override
  State<ComplaintsMap> createState() => _ComplaintsMapState();
}

class _ComplaintsMapState extends State<ComplaintsMap> {
  final MapController _mc = MapController();
  LatLng? _me;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final p = await currentPosition();
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    try {
      _mc.move(_me!, 15);
    } catch (_) {}
  }

  void _preview(Complaint c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ComplaintCard(c: c, user: widget.user),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Complaint>>(
      stream: complaintsStream(),
      builder: (context, snap) {
        final list = (snap.data ?? <Complaint>[]).where(widget.filter).toList();
        final center = _me ?? (list.isNotEmpty ? LatLng(list.first.lat, list.first.lng) : defaultCenter);
        return Stack(
          children: [
            FlutterMap(
              mapController: _mc,
              options: MapOptions(initialCenter: center, initialZoom: 16),
              children: [
                TileLayer(urlTemplate: osmTiles, userAgentPackageName: osmAgent),
                MarkerLayer(
                  markers: [
                    if (_me != null)
                      Marker(
                        point: _me!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    for (final c in list)
                      Marker(
                        point: LatLng(c.lat, c.lng),
                        width: 38,
                        height: 38,
                        child: GestureDetector(
                          onTap: () => _preview(c),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: statusColor(c.status), width: 3),
                              boxShadow: const [
                                BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
                              ],
                            ),
                            child: Icon(categoryOf(c.category).icon, size: 18, color: statusColor(c.status)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 64,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${list.length} issues', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      for (final s in const ['Assigned', 'In Progress', 'Resolved'])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 9, color: statusColor(s)),
                            const SizedBox(width: 4),
                            Text(s, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Text('© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
            ),
            Positioned(
              right: 12,
              top: 10,
              child: FloatingActionButton.small(
                heroTag: null,
                onPressed: _locate,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bell with unread badge; pops a banner the moment a new notification arrives.
class NotificationBell extends StatefulWidget {
  final AppUser user;
  const NotificationBell({super.key, required this.user});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  StreamSubscription<List<AppNotification>>? _sub;
  int _unread = 0;
  Set<String>? _seen;

  @override
  void initState() {
    super.initState();
    _sub = notificationsStream(widget.user.uid).listen((list) {
      if (!mounted) return;
      final ids = list.map((n) => n.id).toSet();
      if (_seen != null) {
        for (final n in list) {
          if (!_seen!.contains(n.id) && !n.read) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${n.title}: ${n.body}'),
              action: SnackBarAction(
                label: 'VIEW',
                onPressed: () => openDetail(context, n.complaintId, widget.user),
              ),
            ));
            break;
          }
        }
      }
      _seen = ids;
      setState(() => _unread = list.where((n) => !n.read).length);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => NotificationsScreen(user: widget.user)),
      ),
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  final AppUser user;
  const NotificationsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<AppNotification>>(
        stream: notificationsStream(user.uid),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return const Center(child: Text('No notifications yet'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = list[i];
              return ListTile(
                tileColor: n.read ? null : Theme.of(context).colorScheme.primaryContainer,
                leading: Icon(n.read ? Icons.notifications_none : Icons.notifications_active),
                title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${n.body}\n${fmtDate(n.at)}'),
                isThreeLine: true,
                onTap: () {
                  if (!n.read) markRead(n.id);
                  if (n.complaintId.isNotEmpty) openDetail(context, n.complaintId, user);
                },
              );
            },
          );
        },
      ),
    );
  }
}

List<Widget> homeActions(BuildContext context, AppUser user) => [
      NotificationBell(user: user),
      IconButton(tooltip: 'Sign out', onPressed: signOut, icon: const Icon(Icons.logout)),
    ];


/// Hand-built village scene used as the app's banner.
class VillageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const VillageHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 190,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD58A), Color(0xFFFFF1CF)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(top: 14, right: 22, child: Icon(Icons.wb_sunny, size: 46, color: Color(0xFFF28C28))),
            Positioned(
              left: -40,
              right: -40,
              bottom: -70,
              child: Container(
                height: 130,
                decoration: const BoxDecoration(
                  color: Color(0xFF7CB342),
                  borderRadius: BorderRadius.all(Radius.elliptical(400, 130)),
                ),
              ),
            ),
            const Positioned(left: 18, bottom: 30, child: Icon(Icons.cottage, size: 46, color: Color(0xFFB5532B))),
            const Positioned(left: 72, bottom: 28, child: Icon(Icons.park, size: 38, color: Color(0xFF2E6B3A))),
            const Positioned(right: 20, bottom: 30, child: Icon(Icons.agriculture, size: 42, color: Color(0xFF8D5524))),
            const Positioned(right: 74, bottom: 28, child: Icon(Icons.grass, size: 30, color: Color(0xFF2E6B3A))),
            Positioned(
              left: 0,
              right: 0,
              top: 28,
              child: Column(
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF7A3E12))),
                  Text(subtitle, style: const TextStyle(fontSize: 14, color: Color(0xFF7A3E12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


final ShapeBorder kCardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(14),
  side: const BorderSide(color: Color(0xFFE5E5EA)),
);

const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [Color(0xFF1C1C1E), Color(0xFF1C1C1E)],
);

Widget barGradient() => Container(decoration: const BoxDecoration(gradient: kBrandGradient));

/// Login banner.
class AppHero extends StatelessWidget {
  const AppHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(gradient: kBrandGradient, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
            child: const Icon(Icons.location_city, size: 40, color: Color(0xFF111111)),
          ),
          const SizedBox(height: 12),
          const Text('CityPulse',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFFFFFFF), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          const Text('Report it. Track it. Get it fixed.', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final t in const ['Report', 'Track', 'Resolve'])
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live summary strip under the citizen app bar.
class CitizenStats extends StatelessWidget {
  final AppUser user;
  const CitizenStats({super.key, required this.user});

  Widget _tile(String label, Object n, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            Text('$n', style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Complaint>>(
      stream: complaintsStream(),
      builder: (context, snap) {
        final all = snap.data ?? <Complaint>[];
        final mine = all.where((x) => x.createdBy == user.uid).length;
        final open = all.where((x) => x.isOpen).length;
        final fixed = all.where((x) => x.status == 'Resolved').length;
        final pulse = all.isEmpty ? 100 : (fixed * 100 / all.length).round();
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
          decoration: const BoxDecoration(
            gradient: kBrandGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(0)),
          ),
          child: Row(
            children: [
              _tile('My reports', mine, Icons.assignment_ind_outlined),
              _tile('Open issues', open, Icons.pending_actions),
              _tile('Fixed', fixed, Icons.verified_outlined),
              _tile('City pulse', '$pulse%', Icons.monitor_heart_outlined),
            ],
          ),
        );
      },
    );
  }
}

final Map<String, Uint8List> _photoCache = <String, Uint8List>{};

/// Decodes a photo once and reuses it, so lists scroll smoothly.
Uint8List photoBytes(String data) {
  final hit = _photoCache[data];
  if (hit != null) return hit;
  if (_photoCache.length > 80) _photoCache.clear();
  final bytes = base64Decode(data);
  _photoCache[data] = bytes;
  return bytes;
}

/// Compact list row used in the pull-up sheet over the map.
class IssueRow extends StatelessWidget {
  final Complaint c;
  final AppUser user;
  const IssueRow({super.key, required this.c, required this.user});

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(c.category);
    final color = statusColor(c.status);
    final sla = slaText(c);
    final tail = sla.isEmpty ? '' : ' · $sla';
    return InkWell(
      onTap: () => openDetail(context, c.id, user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
              child: Icon(cat.icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${c.category} · ${c.status}$tail',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: sla == 'Overdue' ? Colors.red : Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, size: 16, color: Colors.grey.shade600),
                Text('${c.supporters.length}', style: const TextStyle(fontSize: 11)),
              ],
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
