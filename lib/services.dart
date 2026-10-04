import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'otp_service.dart';

final FirebaseFirestore _db = FirebaseFirestore.instance;
final FirebaseAuth _auth = FirebaseAuth.instance;

CollectionReference<Map<String, dynamic>> get usersCol => _db.collection('users');
CollectionReference<Map<String, dynamic>> get complaintsCol => _db.collection('complaints');
CollectionReference<Map<String, dynamic>> get notificationsCol => _db.collection('notifications');

// ---------- Auth ----------

Future<void> signIn(String email, String password) =>
    _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

Future<void> register({
  required String name,
  required String email,
  required String password,
  required String role,
  String? department,
}) async {
  final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  await usersCol.doc(cred.user!.uid).set({
    'name': name.trim(),
    'email': email.trim(),
    'role': role,
    'department': role == 'officer' ? department : null,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> signOut() => _auth.signOut();

Stream<AppUser?> userStream(String uid) =>
    usersCol.doc(uid).snapshots().map((d) => d.exists ? AppUser.fromDoc(d) : null);

Stream<List<AppUser>> allUsersStream() => usersCol.snapshots().map((s) {
      final l = s.docs.map((d) => AppUser.fromDoc(d)).toList();
      l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return l;
    });

Future<void> updateUserRole(String uid, String role, String? department) =>
    usersCol.doc(uid).update({'role': role, 'department': role == 'officer' ? department : null});

// ---------- Location ----------

Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}

// ---------- Complaints ----------

/// All complaints, newest first. Filtering is done in the UI so no composite
/// Firestore indexes are needed.
Stream<List<Complaint>> complaintsStream() => complaintsCol.snapshots().map((s) {
      final l = s.docs.map((d) => Complaint.fromDoc(d)).toList();
      l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return l;
    });

Stream<Complaint?> complaintStream(String id) =>
    complaintsCol.doc(id).snapshots().map((d) => d.exists ? Complaint.fromDoc(d) : null);

/// Duplicate detection: open complaints of the same category within [radius] metres.
Future<List<Complaint>> findDuplicates(String category, double lat, double lng, {double radius = 200}) async {
  final s = await complaintsCol.where('category', isEqualTo: category).get();
  final l = s.docs
      .map((d) => Complaint.fromDoc(d))
      .where((c) => c.isOpen && distanceMeters(lat, lng, c.lat, c.lng) <= radius)
      .toList();
  l.sort((a, b) => distanceMeters(lat, lng, a.lat, a.lng).compareTo(distanceMeters(lat, lng, b.lat, b.lng)));
  return l;
}

Map<String, dynamic> _entry(String status, String note, String by, [Timestamp? at]) =>
    {'status': status, 'note': note, 'by': by, 'at': at ?? Timestamp.now()};

/// Creates the complaint and runs prioritisation + department assignment.
Future<Complaint> createComplaint({
  required AppUser user,
  required String title,
  required String description,
  required String category,
  required double lat,
  required double lng,
  String landmark = '',
  String? photo,
  String? creatorName,
}) async {
  final cat = categoryOf(category);
  final score = computeScore(category, '$title $description', 0);
  final priority = priorityLabel(score);
  final ref = await complaintsCol.add({
    'title': title.trim(),
    'description': description.trim(),
    'category': category,
    'department': cat.department,
    'status': 'Assigned',
    'priority': priority,
    'score': score,
    'lat': lat,
    'lng': lng,
    'landmark': landmark.trim(),
    'photo': photo,
    'resolutionPhoto': null,
    'resolutionNote': '',
    'createdBy': user.uid,
    'createdByName': creatorName ?? user.name,
    'createdByEmail': creatorName == null ? user.email : '',
    'rating': 0,
    'feedback': '',
    'officerId': null,
    'officerName': null,
    'supporters': <String>[],
    'history': [
      _entry('Submitted', 'Complaint reported with photo and GPS location', creatorName ?? user.name),
      _entry('Prioritized', 'Priority set to $priority (score $score)', 'System'),
      _entry('Assigned', 'Routed to ${cat.department} department', 'System'),
    ],
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  final d = await ref.get();
  return Complaint.fromDoc(d);
}

/// Citizen supports (upvotes) an existing complaint instead of filing a duplicate.
Future<void> toggleSupport(Complaint c, AppUser user) async {
  final has = c.supporters.contains(user.uid);
  final count = c.supporters.length + (has ? -1 : 1);
  final score = computeScore(c.category, '${c.title} ${c.description}', count);
  await complaintsCol.doc(c.id).update({
    'supporters': has ? FieldValue.arrayRemove([user.uid]) : FieldValue.arrayUnion([user.uid]),
    'score': score,
    'priority': priorityLabel(score),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> updateStatus(
  Complaint c,
  String status,
  AppUser by, {
  String note = '',
  String? resolutionPhoto,
  bool takeOwnership = false,
}) async {
  final data = <String, dynamic>{
    'status': status,
    'updatedAt': FieldValue.serverTimestamp(),
    'history': FieldValue.arrayUnion([_entry(status, note, by.name)]),
  };
  if (takeOwnership) {
    data['officerId'] = by.uid;
    data['officerName'] = by.name;
  }
  if (resolutionPhoto != null) data['resolutionPhoto'] = resolutionPhoto;
  if (status == 'Resolved') data['resolutionNote'] = note;
  await complaintsCol.doc(c.id).update(data);
  await notifyFollowers(
    c,
    'Complaint $status',
    '"${c.title}" is now $status.${note.isEmpty ? '' : ' $note'}',
    exclude: by.uid,
  );
  // Email the reporter over SMTP (mobile only, best effort).
  if (otpSupported && c.createdByEmail.isNotEmpty) {
    sendStatusEmail(c.createdByEmail, c.title, status, note).catchError((_) {});
  }
}

/// Citizen rates the resolution (1 to 5 stars).
Future<void> rateComplaint(Complaint c, AppUser by, int rating) async {
  await complaintsCol.doc(c.id).update({
    'rating': rating,
    'updatedAt': FieldValue.serverTimestamp(),
    'history': FieldValue.arrayUnion([_entry('Feedback', 'Citizen rated the work $rating/5', by.name)]),
  });
}

/// Citizen says the problem is not actually fixed: back to the department.
Future<void> reopenComplaint(Complaint c, AppUser by) async {
  await complaintsCol.doc(c.id).update({
    'status': 'Assigned',
    'rating': 0,
    'updatedAt': FieldValue.serverTimestamp(),
    'history': FieldValue.arrayUnion([_entry('Reopened', 'Citizen reported the problem is not fixed', by.name)]),
  });
  if (c.officerId != null && c.officerId!.isNotEmpty) {
    await notificationsCol.add({
      'userId': c.officerId,
      'title': 'Complaint reopened',
      'body': '"${c.title}" was reopened by the citizen.',
      'complaintId': c.id,
      'read': false,
      'at': FieldValue.serverTimestamp(),
    });
  }
}

/// Admin override: move a complaint to another department / officer.
Future<void> reassign(Complaint c, String department, AppUser? officer, AppUser by) async {
  final who = officer == null ? department : '$department (${officer.name})';
  await complaintsCol.doc(c.id).update({
    'department': department,
    'officerId': officer?.uid,
    'officerName': officer?.name,
    'status': 'Assigned',
    'updatedAt': FieldValue.serverTimestamp(),
    'history': FieldValue.arrayUnion([_entry('Assigned', 'Reassigned to $who', by.name)]),
  });
  await notifyFollowers(c, 'Complaint reassigned', '"${c.title}" was assigned to $who.', exclude: by.uid);
  if (officer != null) {
    await notificationsCol.add({
      'userId': officer.uid,
      'title': 'New assignment',
      'body': '"${c.title}" was assigned to you.',
      'complaintId': c.id,
      'read': false,
      'at': FieldValue.serverTimestamp(),
    });
  }
}

// ---------- Notifications ----------

/// Notifies the reporter and every supporter of a complaint.
Future<void> notifyFollowers(Complaint c, String title, String body, {String? exclude}) async {
  final targets = <String>{c.createdBy, ...c.supporters};
  targets.remove(exclude);
  targets.remove('');
  if (targets.isEmpty) return;
  final batch = _db.batch();
  for (final uid in targets) {
    batch.set(notificationsCol.doc(), {
      'userId': uid,
      'title': title,
      'body': body,
      'complaintId': c.id,
      'read': false,
      'at': FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

Stream<List<AppNotification>> notificationsStream(String uid) =>
    notificationsCol.where('userId', isEqualTo: uid).snapshots().map((s) {
      final l = s.docs.map((d) => AppNotification.fromDoc(d)).toList();
      l.sort((a, b) => b.at.compareTo(a.at));
      return l;
    });

Future<void> markRead(String id) => notificationsCol.doc(id).update({'read': true});

// ---------- Demo data ----------

/// Adds sample complaints around a point so the map and dashboard are not empty.
Future<void> seedDemoData(AppUser admin, double lat, double lng) async {
  const samples = <List<Object>>[
    ['Deep pothole near bus stop', 'Large pothole, danger for two-wheelers', 'Pothole', 0.0012, 0.0008],
    ['Streetlight not working', 'Dark stretch for three days', 'Streetlight', -0.0015, 0.0011],
    ['Garbage bin overflowing', 'Bin not cleared for a week', 'Garbage', 0.0021, -0.0014],
    ['Pipeline leakage', 'Water leaking on the main road near school', 'Water Leakage', -0.0008, -0.0019],
    ['Signal not working', 'Traffic signal blinking, junction blocked', 'Traffic', 0.0030, 0.0022],
    ['Broken footpath tiles', 'Tiles broken near the park entrance', 'Other', -0.0026, 0.0004],
  ];
  for (final s in samples) {
    await createComplaint(
      user: admin,
      creatorName: 'Demo Citizen',
      title: s[0] as String,
      description: s[1] as String,
      category: s[2] as String,
      lat: lat + (s[3] as double),
      lng: lng + (s[4] as double),
      landmark: 'Demo data',
    );
  }
}

/// Anyone signed in can comment on a complaint; followers get notified.
Future<void> addComment(Complaint c, AppUser by, String text) async {
  await complaintsCol.doc(c.id).update({
    'comments': FieldValue.arrayUnion([
      {'text': text.trim(), 'by': by.name, 'role': by.role, 'at': Timestamp.now()},
    ]),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await notifyFollowers(c, 'New comment', '${by.name}: ${text.trim()}', exclude: by.uid);
}
