import 'package:flutter/material.dart';

import 'models.dart';
import 'report_screen.dart';
import 'services.dart';
import 'widgets.dart';

// ======================= CITIZEN =======================

class CitizenHome extends StatefulWidget {
  final AppUser user;
  const CitizenHome({super.key, required this.user});

  @override
  State<CitizenHome> createState() => _CitizenHomeState();
}

class _CitizenHomeState extends State<CitizenHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final pages = <Widget>[
      ExploreView(user: user),
      ComplaintList(
        user: user,
        filter: (c) => c.createdBy == user.uid || c.supporters.contains(user.uid),
        emptyText: 'You have not reported or supported anything yet',
      ),
      const HeroesBoard(),
    ];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: barGradient(),
        title: Text('Hi, ${user.name}'),
        actions: homeActions(context, user),
      ),
      body: Column(
        children: [
          CitizenStats(user: user),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ReportScreen(user: user)),
        ),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Report'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.person_pin_outlined), label: 'My reports'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Leaders'),
        ],
      ),
    );
  }
}

/// Full map with a pull-up sheet listing the issues on it.
class ExploreView extends StatefulWidget {
  final AppUser user;
  const ExploreView({super.key, required this.user});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  String _query = '';
  String _cat = 'All';

  bool _match(Complaint c) {
    final q = _query.trim().toLowerCase();
    final okCat = _cat == 'All' || c.category == _cat;
    final okText = q.isEmpty ||
        c.title.toLowerCase().contains(q) ||
        c.description.toLowerCase().contains(q) ||
        c.landmark.toLowerCase().contains(q);
    return okCat && okText;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final chips = <String>['All', for (final c in categories) c.name];
    return Stack(
      children: [
        Positioned.fill(child: ComplaintsMap(user: user, filter: (c) => c.isOpen && _match(c))),
        DraggableScrollableSheet(
          initialChildSize: 0.38,
          minChildSize: 0.12,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, -2))],
              ),
              child: StreamBuilder<List<Complaint>>(
                stream: complaintsStream(),
                builder: (context, snap) {
                  final list = (snap.data ?? <Complaint>[]).where(_match).toList();
                  return ListView(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search problems or landmarks',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      SizedBox(
                        height: 52,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          children: [
                            for (final n in chips)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(n),
                                  selected: _cat == n,
                                  onSelected: (_) => setState(() => _cat = n),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: Text('${list.length} issues',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade700)),
                      ),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No problems match your search')),
                        ),
                      for (final c in list) ...[
                        IssueRow(c: c, user: user),
                        const Divider(height: 1, indent: 72),
                      ],
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Leaderboard: 10 points per report, 2 per supporter gained, 5 per resolved report.
class HeroesBoard extends StatelessWidget {
  const HeroesBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Complaint>>(
      stream: complaintsStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final points = <String, int>{};
        final names = <String, String>{};
        final reports = <String, int>{};
        for (final c in snap.data!) {
          final key = '${c.createdBy}|${c.createdByName}';
          names[key] = c.createdByName;
          reports[key] = (reports[key] ?? 0) + 1;
          points[key] = (points[key] ?? 0) +
              10 +
              c.supporters.length * 2 +
              (c.status == 'Resolved' ? 5 : 0);
        }
        final keys = points.keys.toList()..sort((a, b) => points[b]!.compareTo(points[a]!));
        if (keys.isEmpty) return const Center(child: Text('Report a problem to get on the board'));
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Top reporters', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('10 points per report, 2 per supporter, 5 when it gets resolved.'),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < keys.length && i < 20; i++)
              Card(
                elevation: 0, color: Colors.white, shape: kCardShape,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: i == 0
                        ? const Color(0xFFE9C46A)
                        : (i == 1 ? const Color(0xFFCFD8DC) : const Color(0xFFE6B8A2)),
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text(names[keys[i]] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${reports[keys[i]]} reports'),
                  trailing: Text('${points[keys[i]]} pts',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ======================= OFFICER =======================

class OfficerHome extends StatefulWidget {
  final AppUser user;
  const OfficerHome({super.key, required this.user});

  @override
  State<OfficerHome> createState() => _OfficerHomeState();
}

class _OfficerHomeState extends State<OfficerHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    bool mine(Complaint c) => c.department == user.department;
    final pages = <Widget>[
      ComplaintList(
        user: user,
        byPriority: true,
        filter: (c) => mine(c) && c.isOpen,
        emptyText: 'No open complaints for your department',
      ),
      ComplaintsMap(user: user, filter: (c) => mine(c) && c.isOpen),
      ComplaintList(
        user: user,
        filter: (c) => mine(c) && !c.isOpen,
        emptyText: 'Nothing closed yet',
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: barGradient(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Officer desk', style: TextStyle(fontSize: 18)),
            Text(user.department ?? 'No department', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: homeActions(context, user),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Assigned'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Closed'),
        ],
      ),
    );
  }
}

// ======================= ADMIN =======================

class AdminHome extends StatefulWidget {
  final AppUser user;
  const AdminHome({super.key, required this.user});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;
  String _status = 'All';
  String _dept = 'All';

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final pages = <Widget>[
      _Dashboard(user: user),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status', isDense: true),
                    items: [
                      for (final s in ['All', ...statuses]) DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'All'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _dept,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Department', isDense: true),
                    items: [
                      for (final d in ['All', ...departments])
                        DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _dept = v ?? 'All'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ComplaintList(
              user: user,
              byPriority: true,
              filter: (c) =>
                  (_status == 'All' || c.status == _status) && (_dept == 'All' || c.department == _dept),
              emptyText: 'No complaints match the filters',
            ),
          ),
        ],
      ),
      ComplaintsMap(user: user, filter: (c) => true),
      _UsersTab(admin: user),
    ];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: barGradient(),
        title: const Text('CityPulse Admin'),
        actions: homeActions(context, user),
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Complaints'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Users'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AppUser user;
  const _Dashboard({required this.user});

  Future<void> _seed(BuildContext context) async {
    toast(context, 'Adding demo complaints...');
    try {
      final p = await currentPosition();
      await seedDemoData(user, p?.latitude ?? defaultCenter.latitude, p?.longitude ?? defaultCenter.longitude);
      if (context.mounted) toast(context, 'Demo complaints added.');
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Complaint>>(
      stream: complaintsStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final total = all.length;
        final open = all.where((c) => c.isOpen).length;
        final resolved = all.where((c) => c.status == 'Resolved').length;
        final high = all.where((c) => c.isOpen && c.priority == 'High').length;
        final rate = total == 0 ? 0 : (resolved * 100 / total).round();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(children: [
              _Stat('Total', '$total', Icons.inbox_outlined, Colors.indigo),
              _Stat('Open', '$open', Icons.pending_actions, Colors.orange),
            ]),
            Row(children: [
              _Stat('Resolved', '$resolved ($rate%)', Icons.check_circle_outline, Colors.green),
              _Stat('High priority', '$high', Icons.priority_high, Colors.red),
            ]),
            const SizedBox(height: 8),
            _Bars(
              title: 'By status',
              rows: {for (final s in statuses) s: all.where((c) => c.status == s).length},
              total: total,
              colorFor: statusColor,
            ),
            _Bars(
              title: 'By category',
              rows: {for (final c in categories) c.name: all.where((x) => x.category == c.name).length},
              total: total,
            ),
            _Bars(
              title: 'Open by department',
              rows: {for (final d in departments) d: all.where((x) => x.isOpen && x.department == d).length},
              total: open,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _seed(context),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Add demo complaints near me'),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
                elevation: 0, color: Colors.white, shape: kCardShape,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final String title;
  final Map<String, int> rows;
  final int total;
  final Color Function(String)? colorFor;
  const _Bars({required this.title, required this.rows, required this.total, this.colorFor});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    return Card(
                elevation: 0, color: Colors.white, shape: kCardShape,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            for (final e in rows.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : e.value / total,
                          minHeight: 12,
                          backgroundColor: Colors.grey.shade200,
                          color: colorFor == null ? base : colorFor!(e.key),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text('${e.value}',
                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _UsersTab extends StatelessWidget {
  final AppUser admin;
  const _UsersTab({required this.admin});

  Future<void> _edit(BuildContext context, AppUser u) async {
    String role = u.role;
    String dept = u.department ?? departments.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(u.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setDialog(() => role = v ?? role),
              ),
              if (role == 'officer') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: dept,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Department'),
                  items: [for (final d in departments) DropdownMenuItem(value: d, child: Text(d))],
                  onChanged: (v) => setDialog(() => dept = v ?? dept),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await updateUserRole(u.uid, role, dept);
      if (context.mounted) toast(context, 'User updated.');
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: allUsersStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: users.length,
          itemBuilder: (context, i) {
            final u = users[i];
            return Card(
                elevation: 0, color: Colors.white, shape: kCardShape,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase())),
                title: Text(u.name),
                subtitle: Text('${u.email}\n${u.role}${u.department == null ? '' : ' · ${u.department}'}'),
                isThreeLine: true,
                trailing: u.uid == admin.uid
                    ? const Text('You')
                    : IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, u)),
              ),
            );
          },
        );
      },
    );
  }
}
