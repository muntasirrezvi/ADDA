import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'create_room.dart';
import 'home_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'reel_create.dart';
import 'reels_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = App.i.notifications.stream.listen((n) {
      if (!mounted) return;
      final type = (n['data'] as Map?)?['type'];
      if (type == 'call') return; // the call screen handles this
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.notifications_active, color: C.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (n['body'] != null) Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.mute, fontSize: 12)),
          ])),
        ]),
      ));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _create() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Create', style: serif(22)),
            const SizedBox(height: 14),
            _CreateTile(icon: Icons.mic_external_on, title: 'Start a voice room', sub: 'Host a party, choose a cover and theme', onTap: () {
              Navigator.pop(ctx);
              openCreateRoom(context);
            }),
            const SizedBox(height: 10),
            _CreateTile(icon: Icons.videocam, title: 'Make a reel', sub: 'Record with trending music', onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ReelCreateScreen()));
            }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const HomeScreen(), ReelsScreen(active: _tab == 1), const SizedBox(), const InboxScreen(), const MeScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: App.i.unread,
        builder: (context, unread, _) => NavigationBar(
          selectedIndex: _tab,
          height: 66,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => i == 2 ? _create() : setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Rooms'),
            const NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: 'Reels'),
            NavigationDestination(
              icon: Container(
                width: 46,
                height: 34,
                decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add, color: Color(0xFF1A1206)),
              ),
              label: 'Create',
            ),
            NavigationDestination(
              icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: const Icon(Icons.chat_bubble_outline)),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: 'Inbox',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
          ],
        ),
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: const Color(0xFF1A1206)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(sub, style: const TextStyle(color: C.mute, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right, color: C.mute),
            ]),
          ),
        ),
      );
}
