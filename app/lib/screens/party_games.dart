import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/active_room.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'games_kit.dart';

/// Party games are played live by people in the same room. All moves go through
/// `party_*` functions on the server; everyone sees the same table through realtime updates.

const _kindName = {'ludo': 'Ludo', 'ttt': 'Tic-Tac-Toe', 'rps': 'Rock Paper Scissors', 'luckybag': 'Lucky Bag', 'pk': 'PK Battle', 'bottle': 'Spin the Bottle'};
const _kindArt = {'ludo': 'lk_pin_red', 'ttt': 'piece_x', 'rps': 'rps_scissors', 'luckybag': 'luckybag', 'pk': 'vs', 'bottle': 'bottle'};

String _name(String? id) => '${Profiles.get(id)?['username'] ?? 'Player'}';

Future<Map<String, dynamic>?> _call(BuildContext context, String fn, Map<String, dynamic> params) async {
  try {
    final r = await App.i.rpc(fn, params);
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  } catch (e) {
    if (context.mounted) toast(context, errText(e), bad: true);
    return null;
  }
}

/// Entry point from the games sheet.
Future<void> startPartyGame(BuildContext context, {required int roomId, required String kind, ActiveRoom? room}) async {
  final minBet = App.i.number('min_bet', 10000).toInt();
  switch (kind) {
    case 'bottle':
      final g = await _call(context, 'party_create', {'p_room': roomId, 'p_kind': 'bottle', 'p_opts': {}});
      if (g != null) Sfx.play('whoosh');
      return;
    case 'luckybag':
      final opts = await showModalBottomSheet<Map<String, dynamic>>(context: context, builder: (_) => _LuckyBagSetup(minBet: minBet));
      if (opts == null || !context.mounted) return;
      final g = await _call(context, 'party_create', {'p_room': roomId, 'p_kind': 'luckybag', 'p_opts': opts});
      if (g != null) {
        Sfx.play('coin');
        unawaited(App.i.refreshWallet());
      }
      return;
    case 'pk':
      if (room == null || !room.isAdmin) return toast(context, 'Only the room owner or a room admin can start a PK battle');
      final seated = room.seats.where((s) => s['user_id'] != null).map((s) => s['user_id'] as String).toList();
      if (seated.length < 2) return toast(context, 'Two people need to be on the mic');
      await Profiles.load(seated);
      if (!context.mounted) return;
      final opts = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, builder: (_) => _PkSetup(people: seated));
      if (opts == null || !context.mounted) return;
      await _call(context, 'party_create', {'p_room': roomId, 'p_kind': 'pk', 'p_opts': opts});
      return;
    default:
      final opts = await showModalBottomSheet<Map<String, dynamic>>(context: context, builder: (_) => _TableSetup(kind: kind, minBet: minBet));
      if (opts == null || !context.mounted) return;
      final g = await _call(context, 'party_create', {'p_room': roomId, 'p_kind': kind, 'p_opts': opts});
      if (g == null || !context.mounted) return;
      unawaited(App.i.refreshWallet());
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PartyGameScreen(gameId: (g['id'] as num).toInt(), initial: g)));
  }
}

// ---------------------------------------------------------------- setup sheets

class _TableSetup extends StatefulWidget {
  const _TableSetup({required this.kind, required this.minBet});
  final String kind;
  final int minBet;
  @override
  State<_TableSetup> createState() => _TableSetupState();
}

class _TableSetupState extends State<_TableSetup> {
  int _stake = 0;
  int _players = 2;
  @override
  Widget build(BuildContext context) {
    final stakes = [0, ...gameChips.where((c) => c >= widget.minBet).take(5)];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            art(_kindArt[widget.kind]!, size: 44),
            const SizedBox(width: 10),
            Text(_kindName[widget.kind]!, style: serif(22)),
          ]),
          const SizedBox(height: 14),
          if (widget.kind == 'ludo') ...[
            const Text('Players', style: TextStyle(color: C.mute)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final n in const [2, 3, 4])
                ChoiceChip(label: Text('$n'), selected: _players == n, selectedColor: C.gold, onSelected: (_) => setState(() => _players = n)),
            ]),
            const SizedBox(height: 12),
          ],
          const Text('Stake per player (winner takes the pot, 5% fee)', style: TextStyle(color: C.mute)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in stakes)
              ChoiceChip(label: Text(s == 0 ? 'Free' : compact(s)), selected: _stake == s, selectedColor: C.gold, onSelected: (_) => setState(() => _stake = s)),
          ]),
          const SizedBox(height: 18),
          PressButton(label: 'OPEN TABLE', onTap: () => Navigator.pop(context, {'stake': _stake, 'players': _players})),
        ]),
      ),
    );
  }
}

class _LuckyBagSetup extends StatefulWidget {
  const _LuckyBagSetup({required this.minBet});
  final int minBet;
  @override
  State<_LuckyBagSetup> createState() => _LuckyBagSetupState();
}

class _LuckyBagSetupState extends State<_LuckyBagSetup> {
  late int _total = math.max(widget.minBet, 100000);
  int _count = 5;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Floaty(child: art('luckybag', size: 64)),
            const SizedBox(width: 10),
            Expanded(child: Text('Send a Lucky Bag', style: serif(22))),
          ]),
          const Text('People in the room grab a random share. Whatever is left after 10 minutes comes back to you.', style: TextStyle(color: C.mute, fontSize: 12)),
          const SizedBox(height: 14),
          const Text('Total coins', style: TextStyle(color: C.mute)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in [10000, 50000, 100000, 500000, 1000000, 5000000].where((c) => c >= widget.minBet))
              ChoiceChip(label: Text(compact(s)), selected: _total == s, selectedColor: C.gold, onSelected: (_) => setState(() => _total = s)),
          ]),
          const SizedBox(height: 12),
          const Text('How many people can grab', style: TextStyle(color: C.mute)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final n in const [3, 5, 10, 20, 50]) ChoiceChip(label: Text('$n'), selected: _count == n, selectedColor: C.gold, onSelected: (_) => setState(() => _count = n)),
          ]),
          const SizedBox(height: 18),
          PressButton(label: 'SEND ${compact(_total)}', color: const Color(0xFFE0485A), onTap: () => Navigator.pop(context, {'total': _total, 'count': _count})),
        ]),
      ),
    );
  }
}

class _PkSetup extends StatefulWidget {
  const _PkSetup({required this.people});
  final List<String> people;
  @override
  State<_PkSetup> createState() => _PkSetupState();
}

class _PkSetupState extends State<_PkSetup> {
  final List<String> _pick = [];
  int _mins = 3;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [art('vs', size: 48), const SizedBox(width: 10), Text('PK Battle', style: serif(22))]),
          const Text('Pick two people on the mic. Gifts they receive during the battle are their score.', style: TextStyle(color: C.mute, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final id in widget.people)
              GestureDetector(
                onTap: () => setState(() {
                  if (_pick.contains(id)) {
                    _pick.remove(id);
                  } else if (_pick.length < 2) {
                    _pick.add(id);
                  }
                }),
                child: Column(children: [
                  Avatar(profile: Profiles.get(id), size: 52, ring: _pick.contains(id) ? (_pick.indexOf(id) == 0 ? const Color(0xFFE0485A) : const Color(0xFF3A7BFF)) : null),
                  SizedBox(width: 64, child: Text(_name(id), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in const [1, 3, 5, 10]) ChoiceChip(label: Text('$m min'), selected: _mins == m, selectedColor: C.gold, onSelected: (_) => setState(() => _mins = m)),
          ]),
          const SizedBox(height: 18),
          PressButton(
            label: 'START PK',
            onTap: _pick.length == 2 ? () => Navigator.pop(context, {'a': _pick[0], 'b': _pick[1], 'minutes': _mins}) : null,
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- live layer inside the room

/// Floating party UI on top of the room: PK scoreboard, lucky bags, open tables,
/// and the spin-the-bottle show that everyone in the room sees at the same moment.
class PartyLayer extends StatefulWidget {
  const PartyLayer({super.key, required this.room});
  final ActiveRoom room;
  @override
  State<PartyLayer> createState() => _PartyLayerState();
}

class _PartyLayerState extends State<PartyLayer> {
  final Map<int, Map<String, dynamic>> _games = {};
  RealtimeChannel? _ch;
  Timer? _tidy;
  Map<String, dynamic>? _bottle;

  int get _roomId => widget.room.id;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = db
        .channel('party:$_roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_games',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: _roomId),
          callback: (p) => _onRow(p.newRecord, inserted: p.eventType == PostgresChangeEvent.insert),
        )
        .subscribe();
    _tidy = Timer.periodic(const Duration(seconds: 30), (_) => _runTidy());
  }

  @override
  void dispose() {
    _tidy?.cancel();
    if (_ch != null) db.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _runTidy() async {
    try {
      await App.i.rpc('party_tidy', {'p_room': _roomId});
    } catch (_) {}
  }

  Future<void> _load() async {
    await _runTidy();
    try {
      final rows = await db.from('room_games').select().eq('room_id', _roomId).inFilter('status', ['waiting', 'playing']).order('id', ascending: false).limit(20);
      for (final r in rows) {
        _games[(r['id'] as num).toInt()] = Map<String, dynamic>.from(r);
      }
      await Profiles.load(_games.values.expand((g) => [g['host_id'] as String?, ...List<String>.from(g['players'] as List? ?? const [])]));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _onRow(Map<String, dynamic> row, {required bool inserted}) async {
    if (row.isEmpty) return;
    final id = (row['id'] as num).toInt();
    await Profiles.load([row['host_id'] as String?, ...List<String>.from(row['players'] as List? ?? const [])]);
    if (!mounted) return;
    if (row['kind'] == 'bottle') {
      if (inserted) setState(() => _bottle = row);
      return;
    }
    setState(() {
      if (row['status'] == 'waiting' || row['status'] == 'playing') {
        _games[id] = row;
      } else if (row['kind'] == 'pk' && row['status'] == 'done') {
        _games[id] = row;
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted) setState(() => _games.remove(id));
        });
      } else {
        _games.remove(id);
      }
    });
    if (inserted && row['kind'] == 'luckybag') Sfx.play('coin');
  }

  @override
  Widget build(BuildContext context) {
    final list = _games.values.toList()..sort((a, b) => (b['id'] as num).compareTo(a['id'] as num));
    final pk = list.where((g) => g['kind'] == 'pk').firstOrNull;
    final rest = list.where((g) => g['kind'] != 'pk').take(4).toList();
    final top = MediaQuery.of(context).size.height * .36;
    return Stack(children: [
      Positioned(
        right: 8,
        top: top,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (pk != null) _PkCard(game: pk, onTidy: _runTidy),
          for (final g in rest)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: g['kind'] == 'luckybag' ? _BagChip(game: g) : _TableChip(game: g),
            ),
        ]),
      ),
      if (_bottle != null)
        Positioned.fill(
          child: _BottleShow(
            key: ValueKey(_bottle!['id']),
            game: _bottle!,
            onDone: () => setState(() => _bottle = null),
          ),
        ),
    ]);
  }
}

class _TableChip extends StatelessWidget {
  const _TableChip({required this.game});
  final Map<String, dynamic> game;
  @override
  Widget build(BuildContext context) {
    final players = List<String>.from(game['players'] as List);
    final waiting = game['status'] == 'waiting';
    final mine = players.contains(myId);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PartyGameScreen(gameId: (game['id'] as num).toInt(), initial: game))),
      child: Container(
        width: 86,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: waiting ? C.gold : Colors.white24, width: waiting ? 1.5 : 1),
        ),
        child: Column(children: [
          Floaty(amp: 2, child: art(_kindArt[game['kind']]!, size: 40)),
          Text(_kindName[game['kind']]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(gradient: waiting ? C.goldGrad : null, color: waiting ? null : const Color(0xFF2A9D7F), borderRadius: BorderRadius.circular(10)),
            child: Text(
              waiting ? (mine ? 'Waiting ${players.length}/${game['max_players']}' : 'Join') : (mine ? 'Your game' : 'Watch'),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: waiting ? const Color(0xFF1A1206) : Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BagChip extends StatefulWidget {
  const _BagChip({required this.game});
  final Map<String, dynamic> game;
  @override
  State<_BagChip> createState() => _BagChipState();
}

class _BagChipState extends State<_BagChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = Map<String, dynamic>.from(widget.game['state'] as Map);
    return GestureDetector(
      onTap: () => showDialog<void>(context: context, builder: (_) => _GrabDialog(game: widget.game)),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          final wiggle = t < .3 ? math.sin(t / .3 * math.pi * 4) * .12 : 0.0;
          return Transform.rotate(angle: wiggle, child: Transform.translate(offset: Offset(0, t < .3 ? -math.sin(t / .3 * math.pi) * 6 : 0), child: child));
        },
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFF3A4A).withValues(alpha: .45), blurRadius: 18)]),
              child: art('luckybag'),
            ),
            Positioned(
              right: -4,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFE0485A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white, width: 1)),
                child: Text('${st['left_count']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(gradient: C.goldGrad, borderRadius: BorderRadius.circular(10)),
            child: const Text('GRAB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF1A1206))),
          ),
        ]),
      ),
    );
  }
}

class _GrabDialog extends StatefulWidget {
  const _GrabDialog({required this.game});
  final Map<String, dynamic> game;
  @override
  State<_GrabDialog> createState() => _GrabDialogState();
}

class _GrabDialogState extends State<_GrabDialog> with TickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  int? _amount;
  String? _error;
  List<Map<String, dynamic>> _grabs = [];

  int get _id => (widget.game['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _grab();
  }

  @override
  void dispose() {
    _shake.dispose();
    _open.dispose();
    super.dispose();
  }

  Future<void> _grab() async {
    Sfx.play('pop');
    final f = _shake.forward(from: 0);
    try {
      final r = Map<String, dynamic>.from(await App.i.rpc('luckybag_grab', {'p_id': _id}) as Map);
      await f;
      _amount = (r['amount'] as num).toInt();
      Sfx.play('coin');
      if (r['again'] != true) Future.delayed(const Duration(milliseconds: 300), () => Sfx.play('win'));
      unawaited(App.i.refreshWallet());
    } catch (e) {
      await f;
      _error = errText(e);
    }
    try {
      final rows = await db.from('luckybag_grabs').select().eq('game_id', _id).order('amount', ascending: false);
      _grabs = List<Map<String, dynamic>>.from(rows);
      await Profiles.load(_grabs.map((g) => g['user_id'] as String?));
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    _open.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.game['host_id'] as String?;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF9A1424), Color(0xFF4A0610)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: C.gold, width: 2),
          boxShadow: [BoxShadow(color: const Color(0xFFFF3A4A).withValues(alpha: .4), blurRadius: 30)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Avatar(profile: Profiles.get(host), size: 26),
            const SizedBox(width: 6),
            Flexible(child: Text("${_name(host)}'s Lucky Bag", overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: AnimatedBuilder(
              animation: Listenable.merge([_shake, _open]),
              builder: (_, __) {
                final s = _shake.value;
                final o = Curves.easeOutBack.transform(_open.value);
                return Stack(alignment: Alignment.center, children: [
                  Opacity(
                    opacity: (1 - _open.value * 1.5).clamp(0.0, 1.0),
                    child: Transform.rotate(angle: math.sin(s * math.pi * 8) * .18 * (1 - s), child: art('luckybag', size: 130)),
                  ),
                  if (_amount != null)
                    Transform.scale(scale: .3 + .7 * o, child: Opacity(opacity: _open.value.clamp(0.0, 1.0), child: art('coins_pile', size: 140))),
                  if (_open.value > .5 && _amount != null) Positioned.fill(child: IgnorePointer(child: CoinShower(progress: _open.value, count: 10))),
                ]);
              },
            ),
          ),
          if (_amount != null) CountUp(_amount!, size: 26),
          if (_error != null) Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          if (_amount == null && _error == null) const Text('Opening…', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          if (_grabs.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(shrinkWrap: true, children: [
                for (var i = 0; i < _grabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Avatar(profile: Profiles.get(_grabs[i]['user_id'] as String?), size: 24),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_name(_grabs[i]['user_id'] as String?), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      if (i == 0 && _grabs.length > 1) const Text('Luckiest  ', style: TextStyle(fontSize: 10, color: C.gold)),
                      CoinText(grouped(_grabs[i]['amount'] as num), size: 13),
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: C.gold))),
        ]),
      ),
    );
  }
}

class _PkCard extends StatefulWidget {
  const _PkCard({required this.game, required this.onTidy});
  final Map<String, dynamic> game;
  final Future<void> Function() onTidy;
  @override
  State<_PkCard> createState() => _PkCardState();
}

class _PkCardState extends State<_PkCard> {
  Timer? _t;
  Map<String, num> _scores = {};
  @override
  void initState() {
    super.initState();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await App.i.rpc('pk_scores', {'p_id': widget.game['id']});
      if (!mounted) return;
      setState(() => _scores = Map<String, num>.from(r as Map));
      final end = DateTime.tryParse('${widget.game['ends_at']}');
      if (widget.game['status'] == 'playing' && end != null && DateTime.now().isAfter(end.add(const Duration(seconds: 2)))) await widget.onTidy();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = List<String>.from(widget.game['players'] as List);
    final a = _scores[p[0]] ?? 0, b = _scores[p[1]] ?? 0;
    final share = a + b == 0 ? .5 : a / (a + b);
    final end = DateTime.tryParse('${widget.game['ends_at']}')?.toLocal();
    final left = end == null ? Duration.zero : end.difference(DateTime.now());
    final done = widget.game['status'] == 'done';
    final winner = widget.game['winner'] as String?;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.gold2),
      ),
      child: Column(children: [
        Row(children: [
          Avatar(profile: Profiles.get(p[0]), size: 30, ring: const Color(0xFFE0485A)),
          Expanded(child: Center(child: art('vs', size: 34))),
          Avatar(profile: Profiles.get(p[1]), size: 30, ring: const Color(0xFF3A7BFF)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              Expanded(flex: (share * 1000).round().clamp(1, 999), child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF6A7A), Color(0xFFB0122B)])))),
              Expanded(flex: ((1 - share) * 1000).round().clamp(1, 999), child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A4ACF), Color(0xFF6A9BFF)])))),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(compact(a), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFFF8A9A))),
          const Spacer(),
          Text(
            done ? (winner == null ? 'Draw' : '${_name(winner)} wins!') : '${left.inMinutes}:${(left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 10, color: C.gold, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Text(compact(b), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF8AB0FF))),
        ]),
      ]),
    );
  }
}

/// Everyone on the mic sits in a circle; the real glass bottle spins and points at the chosen one.
class _BottleShow extends StatefulWidget {
  const _BottleShow({super.key, required this.game, required this.onDone});
  final Map<String, dynamic> game;
  final VoidCallback onDone;
  @override
  State<_BottleShow> createState() => _BottleShowState();
}

class _BottleShowState extends State<_BottleShow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    Sfx.play('whoosh');
    _c.forward().then((_) {
      if (!mounted) return;
      setState(() => _landed = true);
      Sfx.play('pop');
      Future.delayed(const Duration(milliseconds: 3200), () {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = List<String>.from(widget.game['players'] as List);
    final st = Map<String, dynamic>.from(widget.game['state'] as Map);
    final target = st['target'] as String;
    final ti = math.max(0, players.indexOf(target));
    final n = players.length;
    double angleOf(int i) => -math.pi / 2 + i * 2 * math.pi / n;
    final turns = (st['turns'] as num? ?? 5).toInt();
    final jitter = (st['jitter'] as num? ?? 0).toDouble() * (math.pi / n) * .5;
    final end = turns * 2 * math.pi + angleOf(ti) + jitter;
    return GestureDetector(
      onTap: _landed ? widget.onDone : null,
      child: Container(
        color: Colors.black.withValues(alpha: .6),
        child: LayoutBuilder(builder: (context, box) {
          final d = math.min(box.maxWidth, box.maxHeight) * .86;
          final r = d / 2 - 30;
          return Center(
            child: SizedBox(
              width: d,
              height: d + 70,
              child: Stack(alignment: Alignment.center, children: [
                // table
                Positioned(
                  top: 35,
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [Color(0xFF7A4A22), Color(0xFF3A1E0A)]),
                      border: Border.all(color: const Color(0xFF2A1406), width: 8),
                      boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 30)],
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: d / 2 + r * math.cos(angleOf(i)) - 26,
                    top: 35 + d / 2 + r * math.sin(angleOf(i)) - 26,
                    child: AnimatedScale(
                      scale: _landed && i == ti ? 1.35 : 1,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.elasticOut,
                      child: Avatar(profile: Profiles.get(players[i]), size: 52, ring: _landed && i == ti ? C.gold : Colors.white30),
                    ),
                  ),
                Positioned(
                  top: 35 + d / 2 - d * .3,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, child) {
                      final t = Curves.easeOutQuart.transform(_c.value);
                      final wobble = _landed ? 0.0 : math.sin(_c.value * 60) * .015 * (1 - _c.value);
                      return Transform.rotate(angle: end * t + wobble, child: child);
                    },
                    child: SizedBox(width: d * .6, height: d * .6, child: art('bottle')),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _landed ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Column(children: [
                      Text(_name(target), style: serif(26, color: C.gold)),
                      const Text('Truth or dare?', style: TextStyle(color: Colors.white70)),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------- the game screen

class PartyGameScreen extends StatefulWidget {
  const PartyGameScreen({super.key, required this.gameId, this.initial});
  final int gameId;
  final Map<String, dynamic>? initial;
  @override
  State<PartyGameScreen> createState() => _PartyGameScreenState();
}

class _PartyGameScreenState extends State<PartyGameScreen> {
  Map<String, dynamic>? _g;
  RealtimeChannel? _ch;
  Timer? _tick;
  bool _busy = false;
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    _g = widget.initial;
    _refresh();
    _ch = db
        .channel('game:${widget.gameId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'room_games',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.gameId),
          callback: (p) => _apply(p.newRecord),
        )
        .subscribe();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_ch != null) db.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await db.from('room_games').select().eq('id', widget.gameId).single();
      await _apply(Map<String, dynamic>.from(r));
    } catch (_) {}
  }

  Future<void> _apply(Map<String, dynamic> row) async {
    if (row.isEmpty) return;
    await Profiles.load([row['host_id'] as String?, row['winner'] as String?, ...List<String>.from(row['players'] as List? ?? const [])]);
    if (!mounted) return;
    setState(() => _g = row);
    if (row['status'] == 'done' && !_celebrated) {
      _celebrated = true;
      unawaited(App.i.refreshWallet());
      Sfx.play(row['winner'] == myId ? 'win' : 'lose');
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await _call(context, fn, params);
    if (r != null) await _apply(r);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> move(Map<String, dynamic> m) => _rpc('party_move', {'p_id': widget.gameId, 'p_move': m});

  @override
  Widget build(BuildContext context) {
    final g = _g;
    if (g == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.gold)));
    final kind = g['kind'] as String;
    final players = List<String>.from(g['players'] as List);
    final status = g['status'] as String;
    final stake = (g['stake'] as num).toInt();
    final inGame = players.contains(myId);
    final color = switch (kind) { 'ludo' => const Color(0xFF3A1F6E), 'ttt' => const Color(0xFF3A0E22), _ => const Color(0xFF1E1E2A) };
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_kindName[kind]!),
        actions: [
          if (stake > 0)
            Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: CoinText('Pot ${compact(stake * players.length)}'))),
        ],
      ),
      body: Felt(
        color: color,
        child: SafeArea(
          child: Column(children: [
            if (kind != 'ludo' || status == 'waiting') _playersBar(g, players),
            Expanded(
              child: switch (status) {
                'waiting' => _lobby(g, players, inGame),
                'cancelled' => const Center(child: Text('This table was closed. Stakes were returned.', style: TextStyle(color: C.mute))),
                _ => Stack(children: [
                    Positioned.fill(
                      child: switch (kind) {
                        'ttt' => _TttView(game: g, onMove: move, busy: _busy),
                        'rps' => _RpsView(game: g, onMove: move, busy: _busy),
                        _ => _LudoView(game: g, onMove: move, busy: _busy),
                      },
                    ),
                    if (status == 'done') Positioned.fill(child: _DoneOverlay(game: g)),
                  ]),
              },
            ),
            _footer(g, players, inGame),
          ]),
        ),
      ),
    );
  }

  Widget _playersBar(Map<String, dynamic> g, List<String> players) {
    final st = Map<String, dynamic>.from(g['state'] as Map? ?? const {});
    final turn = (st['turn'] as num?)?.toInt();
    final colors = List<String>.from(st['colors'] as List? ?? const []);
    return SizedBox(
      height: 78,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < players.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: g['status'] == 'playing' && turn == i ? [BoxShadow(color: C.gold.withValues(alpha: .9), blurRadius: 16, spreadRadius: 2)] : null,
                ),
                child: Avatar(profile: Profiles.get(players[i]), size: 44, ring: colors.length > i ? _ludoColor(colors[i]) : (g['kind'] == 'ttt' ? (i == 0 ? const Color(0xFFFF4A6A) : const Color(0xFF3AA0FF)) : null)),
              ),
              SizedBox(width: 70, child: Text(players[i] == myId ? 'You' : _name(players[i]), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
            ]),
          ),
      ]),
    );
  }

  Widget _lobby(Map<String, dynamic> g, List<String> players, bool inGame) {
    final max = (g['max_players'] as num).toInt();
    final host = g['host_id'] == myId;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Floaty(amp: 6, child: art(_kindArt[g['kind']]!, size: 130)),
      const SizedBox(height: 16),
      Text('Waiting for players  ${players.length}/$max', style: serif(20)),
      const SizedBox(height: 6),
      if ((g['stake'] as num) > 0) Text('Stake ${grouped(g['stake'] as num)} coins each · winner takes the pot', style: const TextStyle(color: C.mute, fontSize: 12)),
      const SizedBox(height: 22),
      if (!inGame)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: PressButton(label: (g['stake'] as num) > 0 ? 'JOIN · ${compact(g['stake'] as num)}' : 'JOIN', busy: _busy, onTap: () => _rpc('party_join', {'p_id': widget.gameId})),
        ),
      if (host && g['kind'] == 'ludo' && players.length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 10, 40, 0),
          child: PressButton(label: 'START NOW', color: C.emerald, busy: _busy, onTap: () => _rpc('party_start', {'p_id': widget.gameId})),
        ),
    ]);
  }

  Widget _footer(Map<String, dynamic> g, List<String> players, bool inGame) {
    final status = g['status'];
    if (!inGame || (status != 'waiting' && status != 'playing')) return const SizedBox(height: 8);
    final updated = DateTime.tryParse('${g['updated_at']}')?.toLocal();
    final idle = updated != null && DateTime.now().difference(updated).inSeconds > 42;
    final st = Map<String, dynamic>.from(g['state'] as Map? ?? const {});
    final turn = (st['turn'] as num?)?.toInt();
    final myTurn = turn != null && players.indexOf(myId ?? '') == turn;
    final rpsWaiting = g['kind'] == 'rps' && List<String>.from(st['moved'] as List? ?? const []).contains(myId);
    final canClaim = status == 'playing' && idle && ((g['kind'] != 'rps' && !myTurn) || rpsWaiting);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(children: [
        TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final sure = status == 'waiting' ||
                      await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Leave the game?'),
                              content: const Text('Leaving a running game counts as a loss.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: C.ruby))),
                              ],
                            ),
                          ) ==
                          true;
                  if (!sure) return;
                  await _rpc('party_leave', {'p_id': widget.gameId});
                  if (mounted) Navigator.pop(context);
                },
          icon: const Icon(Icons.logout, size: 18, color: C.mute),
          label: Text(status == 'waiting' && g['host_id'] == myId ? 'Close table' : 'Leave', style: const TextStyle(color: C.mute)),
        ),
        const Spacer(),
        if (canClaim)
          TextButton.icon(
            onPressed: _busy ? null : () => move({'action': 'timeout'}),
            icon: const Icon(Icons.timer_off, size: 18, color: C.gold),
            label: Text(g['kind'] == 'ludo' ? 'Skip idle player' : 'Opponent idle — claim win', style: const TextStyle(color: C.gold)),
          ),
      ]),
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay({required this.game});
  final Map<String, dynamic> game;
  @override
  Widget build(BuildContext context) {
    final winner = game['winner'] as String?;
    final st = Map<String, dynamic>.from(game['state'] as Map? ?? const {});
    final prize = (st['prize'] as num? ?? 0).toInt();
    final draw = st['draw'] == true;
    // starts a moment late so the last move (or the rock-paper-scissors reveal) can be seen first
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -1.2, end: 1),
      duration: const Duration(milliseconds: 2600),
      builder: (_, t, __) => Container(
        color: Colors.black.withValues(alpha: .55 * t.clamp(0.0, 1.0)),
        child: Stack(children: [
          if (winner == myId && t > 0) Positioned.fill(child: IgnorePointer(child: CoinShower(progress: t))),
          if (t > 0)
          Center(
            child: Transform.scale(
              scale: Curves.elasticOut.transform(t.clamp(0.0, 1.0)) * .8 + .2,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (draw) ...[
                  art('coins_pile', size: 110),
                  Text("It's a draw", style: serif(30, color: C.gold)),
                  const Text('Stakes were returned', style: TextStyle(color: C.mute)),
                ] else ...[
                  Avatar(profile: Profiles.get(winner), size: 96, ring: C.gold),
                  const SizedBox(height: 10),
                  Text(winner == myId ? 'You won!' : '${_name(winner)} wins!', style: serif(30, color: C.gold)),
                  if (prize > 0) CountUp(prize, size: 24),
                  if (st['timeout'] != null) const Text('Opponent ran out of time', style: TextStyle(color: C.mute, fontSize: 12)),
                  if (st['forfeit'] != null) const Text('Opponent left the game', style: TextStyle(color: C.mute, fontSize: 12)),
                ],
                const SizedBox(height: 18),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to the room', style: TextStyle(color: C.gold))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Tic-Tac-Toe

class _TttView extends StatelessWidget {
  const _TttView({required this.game, required this.onMove, required this.busy});
  final Map<String, dynamic> game;
  final Future<void> Function(Map<String, dynamic>) onMove;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final st = Map<String, dynamic>.from(game['state'] as Map);
    final board = List<String>.from(st['board'] as List);
    final players = List<String>.from(game['players'] as List);
    final turn = (st['turn'] as num).toInt();
    final myTurn = game['status'] == 'playing' && players.indexOf(myId ?? '') == turn;
    final line = List<int>.from((st['line'] as List? ?? const []).map((e) => (e as num).toInt()));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          game['status'] != 'playing' ? '' : (myTurn ? 'Your turn — you are ${turn == 0 ? 'X' : 'O'}' : "${_name(players[turn])}'s turn"),
          style: serif(18, color: myTurn ? C.gold : Colors.white70),
        ),
      ),
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .0009)
                  ..rotateX(.32),
                child: Container(
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .7), blurRadius: 30, offset: const Offset(0, 24))]),
                  child: Stack(children: [
                    Positioned.fill(child: art('ttt_board', fit: BoxFit.fill)),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: GridView.count(
                          crossAxisCount: 3,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (var i = 0; i < 9; i++)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: myTurn && board[i].isEmpty && !busy
                                    ? () {
                                        Sfx.play('pop');
                                        onMove({'cell': i});
                                      }
                                    : null,
                                child: board[i].isEmpty
                                    ? const SizedBox()
                                    : TweenAnimationBuilder<double>(
                                        key: ValueKey('$i${board[i]}'),
                                        tween: Tween(begin: 0, end: 1),
                                        duration: const Duration(milliseconds: 520),
                                        builder: (_, t, child) => Transform.translate(
                                          offset: Offset(0, -60 * (1 - Curves.bounceOut.transform(t))),
                                          child: Transform.scale(scale: .6 + .4 * t, child: child),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 400),
                                            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: line.contains(i) ? [BoxShadow(color: C.gold.withValues(alpha: .9), blurRadius: 26)] : null),
                                            child: art(board[i] == 'X' ? 'piece_x' : 'piece_o'),
                                          ),
                                        ),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Rock Paper Scissors

const _hands = ['rock', 'paper', 'scissors'];

class _RpsView extends StatefulWidget {
  const _RpsView({required this.game, required this.onMove, required this.busy});
  final Map<String, dynamic> game;
  final Future<void> Function(Map<String, dynamic>) onMove;
  final bool busy;
  @override
  State<_RpsView> createState() => _RpsViewState();
}

class _RpsViewState extends State<_RpsView> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  int _seen = 0;
  String? _picked;

  @override
  void initState() {
    super.initState();
    _seen = _history.length;
    if (widget.game['status'] == 'done' && _seen > 0) _reveal.value = 1;
  }

  @override
  void didUpdateWidget(covariant _RpsView old) {
    super.didUpdateWidget(old);
    if (_history.length > _seen) {
      _seen = _history.length;
      _picked = null;
      Sfx.play('dice');
      _reveal.forward(from: 0).then((_) => Sfx.play('pop'));
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  List<List<String>> get _history => List<List<dynamic>>.from(Map<String, dynamic>.from(widget.game['state'] as Map)['history'] as List? ?? const []).map((e) => List<String>.from(e)).toList();

  @override
  Widget build(BuildContext context) {
    final st = Map<String, dynamic>.from(widget.game['state'] as Map);
    final players = List<String>.from(widget.game['players'] as List);
    final me = players.indexOf(myId ?? '');
    final moved = List<String>.from(st['moved'] as List? ?? const []);
    final iMoved = moved.contains(myId);
    final playing = widget.game['status'] == 'playing';
    final h = _history;
    final last = h.isEmpty ? null : h.last;
    return Column(children: [
      Text('Round ${st['round'] ?? 1}', style: serif(18, color: C.gold)),
      Expanded(
        child: last == null
            ? Center(child: Floaty(amp: 6, child: Row(mainAxisSize: MainAxisSize.min, children: [for (final x in _hands) art('rps_$x', size: 80)])))
            : AnimatedBuilder(
                animation: _reveal,
                builder: (_, __) {
                  final t = _reveal.value;
                  // both fists pump three times, then the hands flip open
                  final pump = t < .6 ? math.sin(t / .6 * math.pi * 3).abs() * 30 : 0.0;
                  final open = t < .6 ? 0.0 : Curves.easeOutBack.transform(((t - .6) / .4).clamp(0.0, 1.0));
                  Widget side(int i, bool left) {
                    final img = open < .5 ? 'rps_rock' : 'rps_${last[i]}';
                    return Transform.translate(
                      offset: Offset(0, -pump),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .002)
                          ..rotateY((open < .5 ? open : 1 - open) * math.pi)
                          ..rotateZ(left ? -.2 : .2),
                        child: art(img, size: 120),
                      ),
                    );
                  }

                  final a = me >= 0 ? me : 0, b = 1 - a;
                  final res = last[a] == last[b] ? 'Draw — again!' : (_beats(last[a], last[b]) ? (me >= 0 ? 'You win the round' : '${_name(players[a])} wins') : (me >= 0 ? 'You lose the round' : '${_name(players[b])} wins'));
                  return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Column(children: [side(a, true), Text(me >= 0 ? 'You' : _name(players[a]))]),
                      art('vs', size: 56),
                      Column(children: [side(b, false), Text(_name(players[b]))]),
                    ]),
                    const SizedBox(height: 12),
                    Opacity(opacity: open, child: Text(res, style: serif(22, color: C.gold))),
                  ]);
                },
              ),
      ),
      if (playing && me >= 0)
        if (iMoved)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_picked != null) Floaty(amp: 3, child: art('rps_$_picked', size: 44)),
              const SizedBox(width: 10),
              const Text('Waiting for your opponent…', style: TextStyle(color: C.mute)),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              for (final x in _hands)
                Expanded(
                  child: GestureDetector(
                    onTap: widget.busy
                        ? null
                        : () {
                            Sfx.play('pop');
                            setState(() => _picked = x);
                            widget.onMove({'hand': x});
                          },
                    child: Container(
                      height: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(colors: [Color(0xFF3A3A4A), Color(0xFF15151E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        border: Border.all(color: C.gold2),
                        boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 6))],
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(children: [
                        Expanded(child: Floaty(amp: 3, phase: _hands.indexOf(x) / 3, child: art('rps_$x'))),
                        Text(x[0].toUpperCase() + x.substring(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
    ]);
  }

  static bool _beats(String a, String b) => (a == 'rock' && b == 'scissors') || (a == 'paper' && b == 'rock') || (a == 'scissors' && b == 'paper');
}

// ---------------------------------------------------------------- Ludo

Color _ludoColor(String c) => switch (c) {
      'red' => const Color(0xFFE0303A),
      'green' => const Color(0xFF1FA84A),
      'yellow' => const Color(0xFFF5C21A),
      _ => const Color(0xFF2F6BE8),
    };

const _ludoOffset = {'red': 0, 'green': 13, 'yellow': 26, 'blue': 39};
const _yardOrigin = {'red': Offset(0, 0), 'green': Offset(9, 0), 'yellow': Offset(9, 9), 'blue': Offset(0, 9)};
const _yardSpots = [Offset(-.9, -.9), Offset(.9, -.9), Offset(-.9, .9), Offset(.9, .9)];

/// The 52 track squares as (column,row) on the 15x15 board, starting at red's start square.
final List<Offset> _track = () {
  final t = <Offset>[];
  for (var c = 1; c <= 5; c++) {
    t.add(Offset(c.toDouble(), 6));
  }
  for (var r = 5; r >= 0; r--) {
    t.add(Offset(6, r.toDouble()));
  }
  t.add(const Offset(7, 0));
  for (var r = 0; r <= 5; r++) {
    t.add(Offset(8, r.toDouble()));
  }
  for (var c = 9; c <= 14; c++) {
    t.add(Offset(c.toDouble(), 6));
  }
  t.add(const Offset(14, 7));
  for (var c = 14; c >= 9; c--) {
    t.add(Offset(c.toDouble(), 8));
  }
  for (var r = 9; r <= 14; r++) {
    t.add(Offset(8, r.toDouble()));
  }
  t.add(const Offset(7, 14));
  for (var r = 14; r >= 9; r--) {
    t.add(Offset(6, r.toDouble()));
  }
  for (var c = 5; c >= 0; c--) {
    t.add(Offset(c.toDouble(), 8));
  }
  t.add(const Offset(0, 7));
  t.add(const Offset(0, 6));
  return t;
}();

Offset _cell(String color, int p, int token) {
  if (p < 0) {
    final o = _yardOrigin[color]!;
    return o + const Offset(2.5, 2.5) + _yardSpots[token];
  }
  if (p <= 50) return _track[(_ludoOffset[color]! + p) % 52];
  if (p >= 56) {
    return switch (color) { 'red' => const Offset(6.3, 7), 'green' => const Offset(7, 6.3), 'yellow' => const Offset(7.7, 7), _ => const Offset(7, 7.7) } + Offset((token - 1.5) * .15, 0);
  }
  final k = (p - 50).toDouble();
  return switch (color) { 'red' => Offset(k, 7), 'green' => Offset(7, k), 'yellow' => Offset(14 - k, 7), _ => Offset(7, 14 - k) };
}

/// Board corners in the rendered board image: 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left.
const _corner = {'red': 0, 'green': 1, 'yellow': 2, 'blue': 3};

/// Turn a board cell a quarter-turn clockwise [k] times around the centre of the 15x15 grid.
Offset _rot(Offset c, int k) {
  var o = c;
  for (var i = 0; i < k; i++) {
    o = Offset(14 - o.dy, o.dx);
  }
  return o;
}

const _turnSeconds = 40;

class _LudoView extends StatefulWidget {
  const _LudoView({required this.game, required this.onMove, required this.busy});
  final Map<String, dynamic> game;
  final Future<void> Function(Map<String, dynamic>) onMove;
  final bool busy;
  @override
  State<_LudoView> createState() => _LudoViewState();
}

class _LudoViewState extends State<_LudoView> with TickerProviderStateMixin {
  /// positions currently drawn, per player per token (may lag behind the server while stepping)
  List<List<int>> _shown = [];
  Timer? _step;
  Timer? _clock;
  late final AnimationController _dice = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  String _lastKey = '';
  String _lastRoll = '';
  String _turnKey = '';
  DateTime _turnSince = DateTime.now();
  String _claimed = '';

  Map<String, dynamic> get _st => Map<String, dynamic>.from(widget.game['state'] as Map);
  List<List<int>> get _tokens => List<List<dynamic>>.from(_st['tokens'] as List).map((t) => t.map((e) => (e as num).toInt()).toList()).toList();
  List<String> get _players => List<String>.from(widget.game['players'] as List);

  @override
  void initState() {
    super.initState();
    _shown = _tokens;
    _lastKey = '${_st['last']}';
    _turnKey = '${_st['turn']}|${_st['rolled']}|${_st['dice']}';
    final upd = DateTime.tryParse('${widget.game['updated_at']}')?.toLocal();
    if (upd != null && DateTime.now().difference(upd).inSeconds < _turnSeconds) _turnSince = upd;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tickClock());
    _maybeAuto();
  }

  void _tickClock() {
    if (!mounted) return;
    setState(() {});
    // when the player on turn has gone quiet, any other player's app skips them
    final me = _players.indexOf(myId ?? '');
    final turn = (_st['turn'] as num).toInt();
    if (widget.game['status'] != 'playing' || me < 0 || me == turn) return;
    if (DateTime.now().difference(_turnSince).inSeconds >= _turnSeconds + 3 && _claimed != _turnKey) {
      _claimed = _turnKey;
      App.i.rpc('party_move', {'p_id': widget.game['id'], 'p_move': {'action': 'timeout'}}).catchError((_) => null);
    }
  }

  @override
  void didUpdateWidget(covariant _LudoView old) {
    super.didUpdateWidget(old);
    final st = _st;
    final last = st['last'] is Map ? Map<String, dynamic>.from(st['last'] as Map) : null;
    final key = '$last';
    final target = _tokens;
    if (key != _lastKey && last != null && last['token'] != null) {
      _lastKey = key;
      _animateMove(last, target);
    } else if (key != _lastKey) {
      _lastKey = key;
      _shown = target;
    } else if (_step == null) {
      _shown = target;
    }
    final tk = '${st['turn']}|${st['rolled']}|${st['dice']}';
    if (tk != _turnKey) {
      _turnKey = tk;
      _turnSince = DateTime.now();
    }
    final rollKey = '${st['dice']}|${st['turn']}|${st['rolled']}|${st['last']}';
    if (last != null && last['roll'] != null && rollKey != _lastRoll) {
      _lastRoll = rollKey;
      Sfx.play('dice', volume: .7);
      _dice.forward(from: 0);
    }
    _maybeAuto();
  }

  void _animateMove(Map<String, dynamic> last, List<List<int>> target) {
    _step?.cancel();
    final by = (last['by'] as num).toInt();
    final tok = (last['token'] as num).toInt();
    final from = (last['from'] as num).toInt();
    final to = (last['to'] as num).toInt();
    final path = <int>[if (from < 0) 0 else for (var p = from + 1; p <= to; p++) p];
    var i = 0;
    _step = Timer.periodic(const Duration(milliseconds: 210), (t) {
      if (!mounted) return t.cancel();
      if (i >= path.length) {
        t.cancel();
        _step = null;
        setState(() => _shown = _tokens);
        if (last['captured'] == true) Sfx.play('boom', volume: .6);
        if (to == 56) Sfx.play('win', volume: .6);
        return;
      }
      Sfx.play('tick', volume: .5);
      setState(() {
        if (_shown.length > by) _shown[by][tok] = path[i];
      });
      i++;
    });
  }

  void _maybeAuto() {
    // if only one token can move, move it for the player (like Ludo King)
    final st = _st;
    final me = _players.indexOf(myId ?? '');
    if (widget.game['status'] != 'playing' || me < 0 || (st['turn'] as num).toInt() != me || st['rolled'] != true) return;
    final movable = List<int>.from((st['movable'] as List).map((e) => (e as num).toInt()));
    if (movable.length == 1) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        final s = _st;
        if (s['rolled'] == true && (s['turn'] as num).toInt() == me) widget.onMove({'action': 'move', 'token': movable.first});
      });
    }
  }

  @override
  void dispose() {
    _step?.cancel();
    _clock?.cancel();
    _dice.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Widget _diceBox({required bool active, required bool ready, required int? dice}) {
    return GestureDetector(
      onTap: ready && !widget.busy ? () => widget.onMove({'action': 'roll'}) : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_dice, _pulse]),
        builder: (_, __) {
          final t = _dice.value;
          final rolling = _dice.isAnimating;
          final img = rolling ? 'die_roll_${(t * 14).floor() % 8}' : (dice == null || ready ? 'die_6' : 'die_$dice');
          return Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ready ? C.gold : Colors.black12, width: ready ? 3 : 1),
              boxShadow: [
                const BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
                if (ready) BoxShadow(color: C.gold.withValues(alpha: .4 + .4 * _pulse.value), blurRadius: 18),
              ],
            ),
            child: Transform.translate(
              offset: Offset(0, rolling ? -math.sin(t * math.pi * 2).abs() * 10 : (ready ? -3 * _pulse.value : 0)),
              child: Transform.rotate(angle: rolling ? (1 - t) * 6 : 0, child: art(img)),
            ),
          );
        },
      ),
    );
  }

  /// A Ludo King style player card that sits outside a corner of the board.
  Widget _panel(int? pi, {required bool left, required List<String> colors, required int turn, required int me, required int? dice}) {
    if (pi == null) return const SizedBox(width: 150, height: 84);
    final col = colors[pi];
    final c = _ludoColor(col);
    final active = widget.game['status'] == 'playing' && pi == turn;
    final out = List<int>.from((_st['out'] as List? ?? const []).map((e) => (e as num).toInt())).contains(pi);
    final home = _tokens.length > pi ? _tokens[pi].where((p) => p == 56).length : 0;
    final left_ = (_turnSeconds - DateTime.now().difference(_turnSince).inMilliseconds / 1000).clamp(0.0, _turnSeconds.toDouble());
    final avatar = SizedBox(
      width: 60,
      height: 60,
      child: Stack(alignment: Alignment.center, children: [
        if (active)
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: left_ / _turnSeconds,
              strokeWidth: 4,
              backgroundColor: Colors.black26,
              color: left_ < 10 ? C.ruby : Colors.white,
            ),
          ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
          child: Opacity(opacity: out ? .4 : 1, child: Avatar(profile: Profiles.get(_players[pi]), size: 48)),
        ),
      ]),
    );
    final info = Column(crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 76,
        child: Text(_players[pi] == myId ? 'You' : _name(_players[pi]),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: left ? TextAlign.left : TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: active ? Colors.white : Colors.white70)),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var k = 0; k < 4; k++)
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 2, top: 3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: k < home ? c : Colors.white24, border: Border.all(color: c, width: 1)),
          ),
      ]),
      if (out) const Text('left', style: TextStyle(fontSize: 10, color: C.mute)),
    ]);
    final box = active ? _diceBox(active: true, ready: pi == me && _st['rolled'] != true, dice: dice) : const SizedBox(width: 58);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [c.withValues(alpha: active ? .55 : .22), Colors.black.withValues(alpha: .35)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: Border.all(color: active ? Colors.white : c.withValues(alpha: .5), width: active ? 2 : 1),
        boxShadow: active ? [BoxShadow(color: c.withValues(alpha: .6), blurRadius: 16)] : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: left ? [avatar, const SizedBox(width: 6), info, const SizedBox(width: 4), box] : [box, const SizedBox(width: 4), info, const SizedBox(width: 6), avatar]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final players = _players;
    final colors = List<String>.from(st['colors'] as List);
    final turn = (st['turn'] as num).toInt();
    final me = players.indexOf(myId ?? '');
    final myTurn = widget.game['status'] == 'playing' && me == turn;
    final rolled = st['rolled'] == true;
    final movable = myTurn && rolled ? List<int>.from((st['movable'] as List).map((e) => (e as num).toInt())) : const <int>[];
    final dice = (st['dice'] as num?)?.toInt();
    // your colour always sits in the bottom-left corner
    final k = me >= 0 ? (3 - _corner[colors[me]]! + 4) % 4 : 0;
    final at = <int, int>{};
    for (var i = 0; i < colors.length; i++) {
      at[(_corner[colors[i]]! + k) % 4] = i;
    }
    Widget panel(int pos) => _panel(at[pos], left: pos == 0 || pos == 3, colors: colors, turn: turn, me: me, dice: dice);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [panel(0), panel(1)]),
      ),
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                final cell = w / 16;
                Offset px(Offset c) => Offset((c.dx + 1) * cell, (c.dy + 1) * cell);
                final pawns = <(double, Widget)>[];
                final seen = <String, int>{};
                for (var pi = 0; pi < _shown.length && pi < colors.length; pi++) {
                  for (var t = 0; t < 4; t++) {
                    final p = _shown[pi][t];
                    final c = _rot(_cell(colors[pi], p, t), k);
                    final key = '${c.dx.toStringAsFixed(1)},${c.dy.toStringAsFixed(1)}';
                    final stack = seen[key] = (seen[key] ?? -1) + 1;
                    final o = px(c) + Offset(stack * cell * .22 - (stack > 0 ? cell * .1 : 0), -stack * cell * .08);
                    final h = cell * 1.55, wd = cell * 1.15;
                    final can = pi == me && movable.contains(t);
                    pawns.add((
                      o.dy,
                      AnimatedPositioned(
                        key: ValueKey('p$pi-$t'),
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOut,
                        left: o.dx - wd / 2,
                        top: o.dy + cell * .34 - h,
                        width: wd,
                        height: h,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: can && !widget.busy
                              ? () {
                                  Sfx.play('pop');
                                  widget.onMove({'action': 'move', 'token': t});
                                }
                              : null,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey('hop$pi-$t-$p'),
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 200),
                            builder: (_, v, child) => Transform.translate(offset: Offset(0, -math.sin(v * math.pi) * cell * .55), child: child),
                            child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                              if (can)
                                AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (_, __) => Container(
                                    width: wd * (.95 + .25 * _pulse.value),
                                    height: wd * (.4 + .1 * _pulse.value),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.all(Radius.elliptical(wd, wd * .4)),
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [BoxShadow(color: _ludoColor(colors[pi]).withValues(alpha: .9), blurRadius: 12, spreadRadius: 1)],
                                    ),
                                  ),
                                ),
                              Transform.translate(
                                offset: Offset(0, can ? -7 * _pulse.value : 0),
                                child: Transform.scale(scale: can ? 1.08 : 1, alignment: Alignment.bottomCenter, child: art('lk_pin_${colors[pi]}', width: wd, height: h)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ));
                  }
                }
                pawns.sort((a, b) => a.$1.compareTo(b.$1));
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 24, offset: const Offset(0, 12))]),
                      child: RotatedBox(quarterTurns: k, child: art('lk_board', fit: BoxFit.fill)),
                    ),
                  ),
                  for (final p in pawns) p.$2,
                ]);
              }),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [panel(3), panel(2)]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          widget.game['status'] != 'playing'
              ? ''
              : myTurn
                  ? (rolled ? (movable.length > 1 ? 'Tap a glowing piece to move' : 'Moving…') : 'Your turn — tap the dice')
                  : "${_name(players[turn])}'s turn",
          style: TextStyle(fontWeight: FontWeight.w700, color: myTurn ? C.gold : Colors.white70),
        ),
      ),
    ]);
  }
}
