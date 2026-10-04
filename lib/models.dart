import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class IssueCategory {
  final String name;
  final String department;
  final IconData icon;
  final int weight;
  const IssueCategory(this.name, this.department, this.icon, this.weight);
}

const categories = <IssueCategory>[
  IssueCategory('Pothole', 'Roads & Transport', Icons.warning_amber_rounded, 30),
  IssueCategory('Streetlight', 'Electrical', Icons.lightbulb_outline, 20),
  IssueCategory('Garbage', 'Sanitation', Icons.delete_outline, 25),
  IssueCategory('Water Leakage', 'Water Supply', Icons.water_drop_outlined, 35),
  IssueCategory('Traffic', 'Traffic Police', Icons.traffic_outlined, 30),
  IssueCategory('Other', 'General Administration', Icons.report_problem_outlined, 10),
];

const departments = <String>[
  'Roads & Transport',
  'Electrical',
  'Sanitation',
  'Water Supply',
  'Traffic Police',
  'General Administration',
];

const statuses = <String>['Assigned', 'In Progress', 'Resolved', 'Rejected'];
const roles = <String>['citizen', 'officer', 'admin'];

const urgentKeywords = <String>[
  'accident', 'danger', 'urgent', 'injur', 'school', 'hospital', 'child',
  'flood', 'fire', 'electric shock', 'open manhole', 'blocked',
];

IssueCategory categoryOf(String name) =>
    categories.firstWhere((c) => c.name == name, orElse: () => categories.last);

/// Priority score: category weight + community support + urgent keywords.
int computeScore(String category, String text, int supporters) {
  int s = categoryOf(category).weight + min<int>(supporters * 10, 50);
  final t = text.toLowerCase();
  for (final k in urgentKeywords) {
    if (t.contains(k)) {
      s += 20;
      break;
    }
  }
  return s;
}

String priorityLabel(int score) =>
    score >= 55 ? 'High' : (score >= 30 ? 'Medium' : 'Low');

/// Haversine distance in metres.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

String fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class AppUser {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? department;
  AppUser({required this.uid, required this.name, required this.email, required this.role, this.department});

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return AppUser(
      uid: d.id,
      name: (m['name'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      role: (m['role'] ?? 'citizen') as String,
      department: m['department'] as String?,
    );
  }

  bool get isCitizen => role == 'citizen';
  bool get isOfficer => role == 'officer';
  bool get isAdmin => role == 'admin';
}

class HistoryEntry {
  final String status;
  final String note;
  final String by;
  final DateTime at;
  HistoryEntry(this.status, this.note, this.by, this.at);
}

class Complaint {
  final String id;
  final String title;
  final String description;
  final String category;
  final String department;
  final String status;
  final String priority;
  final int score;
  final double lat;
  final double lng;
  final String landmark;
  final String? photo;
  final String? resolutionPhoto;
  final String resolutionNote;
  final String createdBy;
  final String createdByName;
  final String? officerId;
  final String? officerName;
  final List<String> supporters;
  final List<HistoryEntry> history;
  final DateTime createdAt;
  final String createdByEmail;
  final int rating;
  final String feedback;
  final List<HistoryEntry> comments;

  Complaint({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.department,
    required this.status,
    required this.priority,
    required this.score,
    required this.lat,
    required this.lng,
    required this.landmark,
    required this.photo,
    required this.resolutionPhoto,
    required this.resolutionNote,
    required this.createdBy,
    required this.createdByName,
    required this.officerId,
    required this.officerName,
    required this.supporters,
    required this.history,
    required this.createdAt,
    required this.createdByEmail,
    required this.rating,
    required this.feedback,
    required this.comments,
  });

  bool get isOpen => status != 'Resolved' && status != 'Rejected';

  factory Complaint.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    final rawHistory = (m['history'] as List<dynamic>?) ?? <dynamic>[];
    final history = <HistoryEntry>[];
    for (final h in rawHistory) {
      final hm = Map<String, dynamic>.from(h as Map);
      history.add(HistoryEntry(
        (hm['status'] ?? '') as String,
        (hm['note'] ?? '') as String,
        (hm['by'] ?? '') as String,
        (hm['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ));
    }
    final comments = <HistoryEntry>[];
    for (final h in (m['comments'] as List<dynamic>?) ?? <dynamic>[]) {
      final hm = Map<String, dynamic>.from(h as Map);
      comments.add(HistoryEntry(
        (hm['role'] ?? '') as String,
        (hm['text'] ?? '') as String,
        (hm['by'] ?? '') as String,
        (hm['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ));
    }
    return Complaint(
      id: d.id,
      title: (m['title'] ?? '') as String,
      description: (m['description'] ?? '') as String,
      category: (m['category'] ?? 'Other') as String,
      department: (m['department'] ?? 'General Administration') as String,
      status: (m['status'] ?? 'Assigned') as String,
      priority: (m['priority'] ?? 'Low') as String,
      score: (m['score'] as num?)?.toInt() ?? 0,
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      landmark: (m['landmark'] ?? '') as String,
      photo: m['photo'] as String?,
      resolutionPhoto: m['resolutionPhoto'] as String?,
      resolutionNote: (m['resolutionNote'] ?? '') as String,
      createdBy: (m['createdBy'] ?? '') as String,
      createdByName: (m['createdByName'] ?? '') as String,
      officerId: m['officerId'] as String?,
      officerName: m['officerName'] as String?,
      supporters: ((m['supporters'] as List<dynamic>?) ?? <dynamic>[]).map((e) => e.toString()).toList(),
      history: history,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdByEmail: (m['createdByEmail'] ?? '') as String,
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      feedback: (m['feedback'] ?? '') as String,
      comments: comments,
    );
  }
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String complaintId;
  final bool read;
  final DateTime at;
  AppNotification(this.id, this.title, this.body, this.complaintId, this.read, this.at);

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};
    return AppNotification(
      d.id,
      (m['title'] ?? '') as String,
      (m['body'] ?? '') as String,
      (m['complaintId'] ?? '') as String,
      (m['read'] ?? false) as bool,
      (m['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Service target by priority: High 24 hours, Medium 72 hours, Low 7 days.
String slaText(Complaint c) {
  if (!c.isOpen) return '';
  final hours = c.priority == 'High' ? 24 : (c.priority == 'Medium' ? 72 : 168);
  final left = c.createdAt.add(Duration(hours: hours)).difference(DateTime.now());
  if (left.isNegative) return 'Overdue';
  if (left.inHours < 1) return 'Due in ${left.inMinutes}m';
  if (left.inHours < 48) return 'Due in ${left.inHours}h';
  return 'Due in ${left.inDays}d';
}
