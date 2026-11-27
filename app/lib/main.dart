import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_screens.dart';
import 'screens/shell.dart';
import 'services/active_room.dart';
import 'services/api.dart';
import 'services/background.dart';
import 'services/errors.dart';
import 'services/presence.dart';
import 'dart:io' show Platform;

import 'screens/wallet_screen.dart' show PlayBilling;
import 'services/calls.dart';
import 'services/tour.dart';
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
  ErrorReporter.install();
  // test builds only: sign in automatically (both values are empty in the real app)
  const autoEmail = String.fromEnvironment('AUTO_LOGIN_EMAIL');
  const autoPass = String.fromEnvironment('AUTO_LOGIN_PASSWORD');
  if (autoEmail.isNotEmpty && db.auth.currentSession == null) {
    try {
      await db.auth.signInWithPassword(email: autoEmail, password: autoPass);
    } catch (e) {
      debugPrint('ADDA auto login failed: $e');
    }
  }
  try {
    await App.i.loadSettings();
  } catch (e, st) {
    ErrorReporter.report(e, st, where: 'loadSettings');
  }
  try {
    await BackgroundAudio.init();
  } catch (e, st) {
    ErrorReporter.report(e, st, where: 'BackgroundAudio.init');
  }
  runApp(const AddaApp());
  Future.delayed(const Duration(seconds: 4), ErrorReporter.reportLastExit);
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
        // the minimised-room bubble floats above every screen. Text follows the phone's font size,
        // but within limits so no screen breaks on very large or very small settings.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: .85, maxScaleFactor: 1.2)),
            child: Stack(fit: StackFit.expand, children: [child ?? const SizedBox(), RoomBubble(navigator: navKey)]),
          );
        },
      );
}

/// Shows sign-in or the app, and keeps the profile loaded.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  static bool _toured = false;
  StreamSubscription<AuthState>? _sub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        OnlineStatus.start();
        if (Platform.isAndroid && App.i.flag('pay_play_enabled')) PlayBilling.i.start(); // finish purchases interrupted last time
      } else {
        CallService.i.stop();
        OnlineStatus.stop();
      }
    } catch (e) {
      _error = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // online status follows the app being open; the room pauses itself if background voice is not allowed
    if (state == AppLifecycleState.resumed && db.auth.currentSession != null) {
      OnlineStatus.start();
    } else if (state == AppLifecycleState.paused) {
      OnlineStatus.stop();
    }
    ActiveRoom.onLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (tourEnabled && !_toured) {
      _toured = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navKey.currentState;
        if (nav != null) runTour(nav);
      });
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
