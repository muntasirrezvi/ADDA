import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _phone = false;
  bool _busy = false;
  bool _hide = true;
  final _id = TextEditingController();
  final _pw = TextEditingController();

  Future<void> _login() async {
    final id = _id.text.trim();
    if (id.isEmpty || _pw.text.isEmpty) return toast(context, 'Enter your ${_phone ? 'phone number' : 'email'} and password', bad: true);
    setState(() => _busy = true);
    try {
      if (_phone) {
        final r = await App.i.fn('login-phone', {'phone': id, 'password': _pw.text});
        final refresh = (r as Map)['refresh_token'] as String?;
        if (refresh == null) throw Exception('Wrong phone number or password');
        await db.auth.setSession(refresh);
      } else {
        await db.auth.signInWithPassword(email: id, password: _pw.text);
      }
    } catch (e) {
      if (mounted) toast(context, e is FunctionException ? 'Wrong phone number or password' : errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgot() async {
    final email = await askText(context, 'Reset password', hint: 'Your email address');
    if (email == null || email.isEmpty || !mounted) return;
    await attempt(context, () => db.auth.resetPasswordForEmail(email), ok: 'If that email has an account, a reset link is on its way.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(-.6, -.8), radius: 1.2, colors: [Color(0xFF2A1F13), C.bg])),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
            ShaderMask(shaderCallback: (r) => C.goldGrad.createShader(r), child: Text('Adda', style: serif(56, color: Colors.white))),
            const Text('Voice rooms, gifts and friends worldwide', style: TextStyle(color: C.mute)),
            const SizedBox(height: 36),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Email'), icon: Icon(Icons.mail_outline)), ButtonSegment(value: true, label: Text('Phone'), icon: Icon(Icons.phone_iphone))],
              selected: {_phone},
              onSelectionChanged: (s) => setState(() {
                _phone = s.first;
                _id.clear();
              }),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF3A2E17) : C.card),
                foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.gold : C.mute),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _id,
              keyboardType: _phone ? TextInputType.phone : TextInputType.emailAddress,
              autofillHints: [_phone ? AutofillHints.telephoneNumber : AutofillHints.email],
              decoration: InputDecoration(labelText: _phone ? 'Phone number (with country code)' : 'Email', hintText: _phone ? '+8801712345678' : 'you@example.com', prefixIcon: Icon(_phone ? Icons.phone : Icons.alternate_email)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: _hide,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _hide = !_hide)),
              ),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?', style: TextStyle(color: C.mute)))),
            const SizedBox(height: 8),
            GoldButton(label: 'Sign in', busy: _busy, onTap: _login),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('New here? ', style: TextStyle(color: C.mute)),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                child: const Text('Create an account', style: TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

const countries = [
  ('BD', 'Bangladesh', '+880'), ('IN', 'India', '+91'), ('PK', 'Pakistan', '+92'), ('NP', 'Nepal', '+977'), ('LK', 'Sri Lanka', '+94'),
  ('SA', 'Saudi Arabia', '+966'), ('AE', 'UAE', '+971'), ('QA', 'Qatar', '+974'), ('KW', 'Kuwait', '+965'), ('OM', 'Oman', '+968'),
  ('BH', 'Bahrain', '+973'), ('EG', 'Egypt', '+20'), ('JO', 'Jordan', '+962'), ('IQ', 'Iraq', '+964'), ('TR', 'Türkiye', '+90'),
  ('MY', 'Malaysia', '+60'), ('SG', 'Singapore', '+65'), ('ID', 'Indonesia', '+62'), ('PH', 'Philippines', '+63'), ('TH', 'Thailand', '+66'),
  ('VN', 'Vietnam', '+84'), ('AU', 'Australia', '+61'), ('JP', 'Japan', '+81'), ('KR', 'South Korea', '+82'), ('GB', 'United Kingdom', '+44'),
  ('US', 'United States', '+1'), ('CA', 'Canada', '+1'), ('IT', 'Italy', '+39'), ('OTHER', 'Other', '+'),
];

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  var _country = countries.first;
  bool _busy = false;
  bool _agree = false;

  Future<void> _signup() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    var phone = _phone.text.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (name.length < 3 || name.length > 20) return toast(context, 'Username must be 3 to 20 characters', bad: true);
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return toast(context, 'Enter a valid email', bad: true);
    if (phone.length < 6) return toast(context, 'Enter your phone number', bad: true);
    if (!phone.startsWith('+')) phone = _country.$3 + phone.replaceFirst(RegExp(r'^0+'), '');
    if (_pw.text.length < 8) return toast(context, 'Password must be at least 8 characters', bad: true);
    if (!_agree) return toast(context, 'Please accept the terms to continue', bad: true);
    setState(() => _busy = true);
    try {
      final r = await db.auth.signUp(email: email, password: _pw.text, data: {'username': name, 'phone': phone, 'country': _country.$2});
      if (!mounted) return;
      if (r.session == null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Check your email', style: serif(20)),
            content: Text('We sent a link to $email. Open it to activate your account, then sign in with your email or phone and password.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: C.gold)))],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      final msg = errText(e);
      if (mounted) {
        toast(context, msg.contains('profile_private_phone_key') || msg.toLowerCase().contains('duplicate') ? 'This phone number already has an account' : msg, bad: true);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: _name, maxLength: 20, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline))),
        const SizedBox(height: 6),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email))),
        const SizedBox(height: 12),
        DropdownButtonFormField<(String, String, String)>(
          value: _country,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.public)),
          items: [for (final c in countries) DropdownMenuItem(value: c, child: Text('${c.$2}  ${c.$3}'))],
          onChanged: (v) => setState(() => _country = v ?? _country),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: 'Phone number', prefixText: '${_country.$3} ', prefixIcon: const Icon(Icons.phone)),
        ),
        const SizedBox(height: 12),
        TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)', prefixIcon: Icon(Icons.lock_outline))),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _agree,
          onChanged: (v) => setState(() => _agree = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: C.gold,
          title: const Text('I am 18 or older and accept the Terms and Privacy Policy', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 12),
        GoldButton(label: 'Create account', busy: _busy, onTap: _signup),
        const SizedBox(height: 12),
        const Text('You will sign in with your email or phone number and this password.', textAlign: TextAlign.center, style: TextStyle(color: C.mute, fontSize: 12)),
      ]),
    );
  }
}
