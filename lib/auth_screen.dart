import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'otp_service.dart';
import 'services.dart';
import 'widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  String _role = 'citizen';
  String _department = departments.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (otpSupported) {
        final verified = await _verifyOtp(_email.text.trim());
        if (!verified) return;
      }
      if (_isLogin) {
        await signIn(_email.text, _password.text);
      } else {
        await register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          department: _department,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends Firebase's password reset email.
  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type your email above, then tap Forgot password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _error = null);
        toast(context, 'Password reset link sent to $email. Check inbox and spam.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  /// Emails a one-time code over SMTP and asks the user to type it in.
  Future<bool> _verifyOtp(String email) async {
    var code = generateOtp();
    var sentAt = DateTime.now();
    try {
      await sendOtpEmail(email, code);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send the OTP email: $e');
      return false;
    }
    if (!mounted) return false;
    final input = TextEditingController();
    String? err;
    bool resending = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Verify your email'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('We sent a 6-digit code to $email. It expires in 5 minutes.'),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(labelText: 'One-time code', errorText: err),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: resending
                  ? null
                  : () async {
                      setDialog(() {
                        resending = true;
                        err = null;
                      });
                      final next = generateOtp();
                      String? failure;
                      try {
                        await sendOtpEmail(email, next);
                        code = next;
                        sentAt = DateTime.now();
                      } catch (_) {
                        failure = 'Resend failed. Try again.';
                      }
                      if (!ctx.mounted) return;
                      setDialog(() {
                        resending = false;
                        err = failure;
                      });
                    },
              child: Text(resending ? 'Sending...' : 'Resend'),
            ),
            FilledButton(
              onPressed: () {
                if (DateTime.now().difference(sentAt).inMinutes >= 5) {
                  setDialog(() => err = 'Code expired. Tap Resend.');
                } else if (input.text.trim() == code) {
                  Navigator.pop(ctx, true);
                } else {
                  setDialog(() => err = 'Wrong code');
                }
              },
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppHero(),
                    const SizedBox(height: 28),
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                      validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
                    ),
                    if (!_isLogin) ...[
                      const SizedBox(height: 16),
                      const Text('I am a', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
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
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _forgot,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isLogin ? 'Sign in' : 'Create account'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _isLogin = !_isLogin;
                                _error = null;
                              }),
                      child: Text(_isLogin ? 'New here? Create an account' : 'Already registered? Sign in'),
                    ),
                    Text(
                      otpSupported
                          ? 'A one-time code will be emailed to you to verify.'
                          : 'Email OTP runs in the mobile app only.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
