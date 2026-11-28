import 'package:flutter/material.dart';

import '../screens/bigsix.dart';
import '../screens/crash_live.dart';
import '../screens/games_tab.dart';
import '../screens/greedy_live.dart';
import '../screens/history_screen.dart';
import '../screens/lucky777.dart';
import '../screens/mines.dart';
import '../screens/profile_screen.dart';
import '../screens/room_screen.dart';
import '../screens/sicbo.dart';
import '../screens/wallet_screen.dart';
import '../widgets/entry_fx.dart';
import '../widgets/gift_fx.dart';
import 'api.dart';

/// Test builds only (--dart-define=TOUR=true): opens the main screens one by one and prints a
/// marker for each, so the emulator test can take a screenshot of every screen.
const tourEnabled = bool.fromEnvironment('TOUR');

Future<void> runTour(NavigatorState nav) async {
  void shot(String name) => debugPrint('ADDA_TOUR shot $name');
  Future<void> wait([int ms = 4500]) => Future.delayed(Duration(milliseconds: ms));
  Future<void> page(String name, Widget w, {int ms = 4500}) async {
    final route = MaterialPageRoute(builder: (_) => w);
    nav.push(route);
    await wait(ms);
    shot(name);
    await wait(3000);
    if (route.isActive) nav.removeRoute(route);
    await wait(800);
  }

  try {
    await App.i.rpc('accept_games');
  } catch (_) {}
  await wait(11000);
  nav.popUntil((r) => r.isFirst);
  await wait(800);
  shot('home');
  await wait(900);
  // gift panel
  final gifts = List<Map<String, dynamic>>.from(await db.from('gifts').select().eq('active', true).order('sort'));
  final bgRoute = MaterialPageRoute(builder: (_) => const Scaffold(body: RoomBackground(themeId: 'galaxy')));
  nav.push(bgRoute);
  await wait(1200);
  final sheet = showModalBottomSheet<void>(
    context: nav.context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GiftSheet(roomId: null, gifts: gifts, people: [myId!], preselect: myId!),
  );
  await wait(2500);
  shot('gift_panel');
  await wait(2500);
  nav.pop();
  await sheet;
  if (bgRoute.isActive) nav.removeRoute(bgRoute);
  await wait(600);

  // entrance and gift animations over a room background
  final stage = GiftStageController();
  final fxRoute = MaterialPageRoute(
    builder: (_) => Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const RoomBackground(themeId: 'galaxy'),
        Positioned(left: 0, right: 0, top: 80, bottom: 0, child: EntryShow(row: {'user_id': myId, 'id': -1}, onDone: () {})),
        GiftStage(controller: stage),
      ]),
    ),
  );
  nav.push(fxRoute);
  await wait(900);
  shot('entry');
  await wait(4500);
  final car = gifts.where((g) => g['id'] == 'car').firstOrNull;
  if (car != null) {
    stage.play(GiftShow(gift: car, from: 'Tester', to: 'Friend', qty: 1));
    await wait(1200);
    shot('gift_car');
    await wait(4000);
  }
  final rose = gifts.where((g) => g['id'] == 'rose').firstOrNull;
  if (rose != null) {
    stage.play(GiftShow(gift: rose, from: 'Tester', to: 'Friend', qty: 10));
    await wait(500);
    shot('gift_rose');
    await wait(2500);
  }
  final palace = gifts.where((g) => g['id'] == 'palace').firstOrNull;
  if (palace != null) {
    stage.play(GiftShow(gift: palace, from: 'Tester', to: 'Friend', qty: 1));
    await wait(2200);
    shot('gift_palace');
    await wait(2500);
  }
  if (fxRoute.isActive) nav.removeRoute(fxRoute);
  await page('me', const Scaffold(body: SafeArea(child: MeScreen())));
  await page('wallet', const WalletScreen());
  await page('history', const HistoryScreen());
  await page('games', GamesTab(openRooms: () {}));
  await page('greedy', const GreedyLive(), ms: 6000);
  await page('fruit', const GreedyLive(cfg: fruitCfg), ms: 6000);
  await page('lucky777', const Lucky777());
  await page('rocket', const CrashLive(), ms: 6000);
  await page('gems', const MinesGame());
  await page('wheel', const BigSixGame());
  await page('dice', const SicBoGame());

  debugPrint('ADDA_TOUR done');
}
