import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_screen.dart';
import 'firebase_options.dart';
import 'homes.dart';
import 'models.dart';
import 'otp_service.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await loadEnv();
  runApp(const CityPulseApp());
}

class CityPulseApp extends StatelessWidget {
  const CityPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1C1C1E),
      primary: const Color(0xFF1C1C1E),
      secondary: const Color(0xFF0A84FF),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
    );
    return MaterialApp(
      title: 'CityPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        chipTheme: ChipThemeData(
          selectedColor: const Color(0xFFD6E9FF),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFD1D1D6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        fontFamily: GoogleFonts.inter().fontFamily,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1C1C1E),
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF0A84FF),
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFD6E9FF),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: fieldBorder,
          enabledBorder: fieldBorder,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Routes the signed-in user to the interface for their role.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final fbUser = snap.data;
        if (fbUser == null) return const AuthScreen();
        return StreamBuilder<AppUser?>(
          stream: userStream(fbUser.uid),
          builder: (context, us) {
            if (us.hasError) {
              return ProfileSetup(
                fbUser: fbUser,
                error: us.error.toString(),
                onSaved: () => setState(() {}),
              );
            }
            if (us.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final user = us.data;
            if (user == null) {
              return ProfileSetup(fbUser: fbUser, onSaved: () => setState(() {}));
            }
            if (user.isAdmin) return AdminHome(user: user);
            if (user.isOfficer) return OfficerHome(user: user);
            return CitizenHome(user: user);
          },
        );
      },
    );
  }
}

/// Shown when a signed-in account has no profile document yet (for example the
/// database was not ready during sign-up). Lets the user finish the profile.
class ProfileSetup extends StatefulWidget {
  final User fbUser;
  final String? error;
  final VoidCallback onSaved;
  const ProfileSetup({super.key, required this.fbUser, required this.onSaved, this.error});

  @override
  State<ProfileSetup> createState() => _ProfileSetupState();
}

class _ProfileSetupState extends State<ProfileSetup> {
  final _name = TextEditingController();
  String _role = 'citizen';
  String _department = departments.first;
  bool _ready = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
    _ready = widget.error != null;
    // Give a normal sign-up a few seconds to write its profile first.
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await usersCol.doc(widget.fbUser.uid).set({
        'name': _name.text.trim(),
        'email': widget.fbUser.email ?? '',
        'role': _role,
        'department': _role == 'officer' ? _department : null,
      }).timeout(const Duration(seconds: 12));
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not save: $e\n\nCheck the Firebase console: Firestore Database must be created and the rules published.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Finish your profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Signed in as ${widget.fbUser.email ?? ''}'),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in roles)
                      ChoiceChip(
                        label: Text(r[0].toUpperCase() + r.substring(1)),
                        selected: _role == r,
                        onSelected: (_) => setState(() => _role = r),
                      ),
                  ],
                ),
                if (_role == 'officer') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [for (final d in departments) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) => setState(() => _department = v ?? departments.first),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving...' : 'Save and continue'),
                ),
                TextButton(onPressed: signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blocks the app until the user clicks the verification link sent to their
/// email. Works for any email domain and on every platform.
class VerifyEmailScreen extends StatefulWidget {
  final User user;
  final VoidCallback onVerified;
  const VerifyEmailScreen({super.key, required this.user, required this.onVerified});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  bool _sending = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _send();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    if (mounted && !_sending) setState(() => _sending = true);
    String message;
    try {
      await widget.user.sendEmailVerification();
      message = 'Verification link sent. Check your inbox and spam folder.';
    } catch (e) {
      message = 'Could not send the email: $e';
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _message = message;
      });
    }
  }

  Future<void> _check() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {}
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
      _timer?.cancel();
      widget.onVerified();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 72, color: Color(0xFF1C1C1E)),
                  const SizedBox(height: 16),
                  const Text('Verify your email',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('We sent a link to ${widget.user.email ?? 'your email'}. Open it, then come back here. '
                      'This screen continues automatically.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  if (_message.isNotEmpty) Text(_message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _check, child: const Text('I have verified')),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? 'Sending...' : 'Resend link'),
                  ),
                  TextButton(onPressed: signOut, child: const Text('Use a different account')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
