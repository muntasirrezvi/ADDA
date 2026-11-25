import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screens.dart';
import 'screens/shell.dart';
import 'services/api.dart';
import 'dart:io' show Platform;

import 'screens/wallet_screen.dart' show PlayBilling;
import 'services/calls.dart';
import 'theme.dart';
import 'widgets/room_bubble.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfig());
    return;
  }
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await App.i.loadSettings();
  runApp(const AddaApp());
}

class AddaApp extends StatelessWidget {
  const AddaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Adda',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorKey: navKey,
        home: const AuthGate(),
        // the minimised-room bubble floats above every screen
        builder: (context, child) => Stack(fit: StackFit.expand, children: [child ?? const SizedBox(), RoomBubble(navigator: navKey)]),
      );
}

/// Shows sign-in or the app, and keeps the profile loaded.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = db.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.initialSession || s.event == AuthChangeEvent.signedOut) _boot();
    });
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (db.auth.currentSession != null) {
        await App.i.loadMe();
        CallService.i.start(navKey);
        if (Platform.isAndroid && App.i.flag('pay_play_enabled')) PlayBilling.i.start(); // finish purchases interrupted last time
      } else {
        CallService.i.stop();
      }
    } catch (e) {
      _error = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (App.i.flag('maintenance')) {
      return const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Adda is being upgraded.\nPlease come back in a little while.', textAlign: TextAlign.center))));
    }
    if (_loading) return const _Splash();
    if (db.auth.currentSession == null) return const LoginScreen();
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: _boot, child: const Text('Try again', style: TextStyle(color: C.gold))),
            TextButton(onPressed: () => App.i.signOut(), child: const Text('Sign out', style: TextStyle(color: C.mute))),
          ]),
        ),
      );
    }
    final me = App.i.me.value;
    if (me != null && me['banned_until'] != null && DateTime.tryParse(me['banned_until'])?.isAfter(DateTime.now()) == true) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.block, size: 48, color: C.ruby),
            const SizedBox(height: 12),
            const Text('Your account is suspended for breaking the community rules.', textAlign: TextAlign.center),
            TextButton(onPressed: () => App.i.signOut(), child: const Text('Sign out', style: TextStyle(color: C.gold))),
          ]),
        ),
      );
    }
    return const Shell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ShaderMask(shaderCallback: (r) => C.goldGrad.createShader(r), child: Text('Adda', style: serif(52, color: Colors.white))),
            const SizedBox(height: 8),
            const Text('VOICE · PARTY · FRIENDS', style: TextStyle(letterSpacing: 4, fontSize: 11, color: C.mute)),
            const SizedBox(height: 28),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.gold)),
          ]),
        ),
      );
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Build the app with --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=...\nSee app/README.md.', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
