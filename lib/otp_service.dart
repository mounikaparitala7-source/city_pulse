import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// Browsers cannot open SMTP sockets, so the web build posts to the small
/// SMTP relay in otp_server.js (run it with: node otp_server.js).
const String _relayUrl = 'http://localhost:8787/send';

/// Loads GMAIL_USER / GMAIL_APP_PASSWORD from the bundled .env file.
Future<void> loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env available: mobile OTP is switched off.
  }
}

String _env(String key) {
  try {
    if (!dotenv.isInitialized) return '';
    return dotenv.env[key] ?? '';
  } catch (_) {
    return '';
  }
}

bool get otpSupported =>
    kIsWeb || (_env('GMAIL_USER').isNotEmpty && _env('GMAIL_APP_PASSWORD').isNotEmpty);

String generateOtp() => (100000 + Random.secure().nextInt(900000)).toString();

Future<void> _sendMail(String to, String subject, String text) async {
  if (kIsWeb) {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_relayUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'to': to, 'subject': subject, 'text': text}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw Exception('OTP mail server is not running. In a new terminal run: node otp_server.js');
    }
    if (res.statusCode != 200) {
      throw Exception('Mail server error: ${res.body}');
    }
    return;
  }
  final user = _env('GMAIL_USER');
  final pass = _env('GMAIL_APP_PASSWORD').replaceAll(' ', '');
  final message = Message()
    ..from = Address(user, 'CityPulse')
    ..recipients.add(to)
    ..subject = subject
    ..text = text;
  await send(message, gmail(user, pass)).timeout(const Duration(seconds: 25));
}

/// Sends the one-time code over Gmail SMTP.
Future<void> sendOtpEmail(String to, String code) {
  return _sendMail(
    to,
    'Your CityPulse verification code: $code',
    'Your CityPulse one-time code is $code.\n\n'
        'It expires in 5 minutes. If you did not request it, ignore this email.',
  );
}

/// Emails the reporter when an officer changes the complaint status.
Future<void> sendStatusEmail(String to, String title, String status, String note) {
  final extra = note.isEmpty ? '' : '\n\nNote from the officer: $note';
  return _sendMail(
    to,
    'CityPulse: your complaint is now $status',
    'Your complaint "$title" is now $status.$extra\n\nOpen the CityPulse app to see the full timeline.',
  );
}
