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
    nav.push(MaterialPageRoute(builder: (_) => w));
    await wait(ms);
    shot(name);
    await wait(900);
    nav.pop();
    await wait(800);
  }

  try {
    await App.i.rpc('accept_games');
  } catch (_) {}
  await wait(6000);
  shot('home');
  await wait(900);
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

  // gift panel
  final gifts = List<Map<String, dynamic>>.from(await db.from('gifts').select().eq('active', true).order('sort'));
  nav.push(MaterialPageRoute(builder: (_) => const Scaffold(body: RoomBackground(themeId: 'galaxy'))));
  await wait(1200);
  final sheet = showModalBottomSheet<void>(
    context: nav.context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GiftSheet(roomId: null, gifts: gifts, people: [myId!], preselect: myId!),
  );
  await wait(2500);
  shot('gift_panel');
  await wait(700);
  nav.pop();
  await sheet;
  await wait(600);

  // entrance and gift animations over a room background
  final stage = GiftStageController();
  nav.push(MaterialPageRoute(
    builder: (_) => Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        const RoomBackground(themeId: 'galaxy'),
        Positioned(left: 0, right: 0, top: 80, bottom: 0, child: EntryShow(row: {'user_id': myId, 'id': -1}, onDone: () {})),
        GiftStage(controller: stage),
      ]),
    ),
  ));
  await wait(1300);
  shot('entry');
  await wait(3500);
  final car = gifts.where((g) => g['id'] == 'car').firstOrNull;
  if (car != null) {
    stage.play(GiftShow(gift: car, from: 'Tester', to: 'Friend', qty: 1));
    await wait(1600);
    shot('gift_car');
    await wait(3200);
  }
  final rose = gifts.where((g) => g['id'] == 'rose').firstOrNull;
  if (rose != null) {
    stage.play(GiftShow(gift: rose, from: 'Tester', to: 'Friend', qty: 10));
    await wait(700);
    shot('gift_rose');
    await wait(2000);
  }
  final palace = gifts.where((g) => g['id'] == 'palace').firstOrNull;
  if (palace != null) {
    stage.play(GiftShow(gift: palace, from: 'Tester', to: 'Friend', qty: 1));
    await wait(2200);
    shot('gift_palace');
    await wait(2500);
  }
  nav.pop();
  debugPrint('ADDA_TOUR done');
}
