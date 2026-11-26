import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'wallet_screen.dart';

Future<Map<String, dynamic>> _walletInfo() async => Map<String, dynamic>.from(await App.i.rpc('wallet_info') as Map);

// =====================================================================================
// Send coins / diamonds to another user (from your wallet, or from an agent/admin store)
// =====================================================================================

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.fromStore = false, this.toPublicId});
  final bool fromStore;
  final int? toPublicId;
  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _id = TextEditingController();
  final _coins = TextEditingController();
  final _diamonds = TextEditingController();
  final _note = TextEditingController();
  Map<String, dynamic>? _to;
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _store;
  bool _busy = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.toPublicId != null) {
      _id.text = '${widget.toPublicId}';
      _lookup();
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_id, _coins, _diamonds, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.fromStore) {
        _store = Map<String, dynamic>.from(await App.i.rpc('my_store') as Map);
      } else {
        _info = await _walletInfo();
      }
      await App.i.refreshWallet();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
  }

  void _onId(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _lookup);
  }

  Future<void> _lookup() async {
    final id = int.tryParse(_id.text.trim());
    if (id == null) return setState(() => _to = null);
    try {
      final r = await App.i.rpc('find_user', {'p_public': id});
      if (mounted) setState(() => _to = r == null ? null : Map<String, dynamic>.from(r as Map));
    } catch (_) {
      if (mounted) setState(() => _to = null);
    }
  }

  int get _c => int.tryParse(_coins.text.replaceAll(',', '')) ?? 0;
  int get _d => int.tryParse(_diamonds.text.replaceAll(',', '')) ?? 0;

  Future<void> _send() async {
    if (_to == null) return toast(context, 'Enter a valid user ID', bad: true);
    if (_c <= 0 && _d <= 0) return toast(context, 'Enter how many coins or diamonds to send', bad: true);
    final what = [if (_c > 0) '${grouped(_c)} coins', if (_d > 0) '${grouped(_d)} diamonds'].join(' + ');
    if (!await confirm(context, 'Send $what?', 'To ${_to!['username']} (ID ${_to!['public_id']}). This cannot be undone.', yes: 'Send')) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      await App.i.rpc(widget.fromStore ? 'store_transfer' : 'user_transfer',
          {'p_to_public': _to!['public_id'], 'p_coins': _c, 'p_diamonds': _d, 'p_note': _note.text.trim()});
      await _load();
    }, ok: 'Sent $what to ${_to!['username']}');
    if (ok) {
      _coins.clear();
      _diamonds.clear();
      _note.clear();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final info = _info;
    final unlimited = store?['unlimited'] == true;
    final fee = (info?['transfer_fee_pct'] as num?) ?? 0;
    final diamondsAllowed = widget.fromStore || info?['transfer_diamonds_enabled'] != false;
    final Object? rawRecent = widget.fromStore ? (store == null ? null : store['recent']) : (info == null ? null : info['recent']);
    final recent = List<Map<String, dynamic>>.from((rawRecent as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    return Scaffold(
      appBar: AppBar(title: Text(widget.fromStore ? 'Agent store' : 'Send coins & diamonds')),
      body: RefreshIndicator(
        color: C.gold,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.fromStore)
            _StoreCard(store: store)
          else
            const _BalanceRow(),
          const SizedBox(height: 8),
          Text(
            widget.fromStore
                ? (unlimited ? 'As an admin you can send any amount. Every transfer is logged.' : 'Send from your agent store to any user. The admin fills your store.')
                : 'Send a gift of coins or diamonds to a friend using their user ID (shown on their profile).${fee > 0 ? ' A $fee% fee applies to coins.' : ''}',
            style: const TextStyle(color: C.mute, fontSize: 12),
          ),
          const Section('Who are you sending to?'),
          TextField(controller: _id, keyboardType: TextInputType.number, onChanged: _onId, decoration: const InputDecoration(labelText: 'User ID', prefixIcon: Icon(Icons.badge, color: C.gold))),
          const SizedBox(height: 8),
          if (_to != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.emerald.withValues(alpha: .5))),
              child: Row(children: [
                Avatar(profile: _to, size: 40),
                const SizedBox(width: 10),
                Expanded(child: Text('${_to!['username']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                LevelBadge((_to!['wealth_level'] as num?)?.toInt() ?? 1),
                const SizedBox(width: 6),
                const Icon(Icons.check_circle, color: C.emerald),
              ]),
            )
          else if (_id.text.trim().isNotEmpty)
            const Text('No user with this ID', style: TextStyle(color: C.ruby, fontSize: 12)),
          const Section('How much?'),
          Row(children: [
            Expanded(child: TextField(controller: _coins, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Coins', prefixIcon: Icon(Icons.monetization_on, color: C.gold)))),
            if (diamondsAllowed) ...[
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _diamonds, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Diamonds', prefixIcon: Icon(Icons.diamond, color: Color(0xFF7FB0FF))))),
            ],
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final v in const [10000, 100000, 1000000, 10000000]) ActionChip(label: Text(compact(v)), onPressed: () => setState(() => _coins.text = '$v')),
          ]),
          TextField(controller: _note, maxLength: 80, decoration: const InputDecoration(labelText: 'Message (optional)')),
          const SizedBox(height: 6),
          GoldButton(label: 'Send', icon: Icons.send, busy: _busy, onTap: _to == null || (_c <= 0 && _d <= 0) ? null : _send),
          const Section('Recent'),
          if (recent.isEmpty) const EmptyState('No transfers yet', icon: Icons.swap_horiz),
          for (final t in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: (t['sent'] == true ? C.ruby : C.emerald).withValues(alpha: .15),
                child: Icon(t['sent'] == true ? Icons.north_east : Icons.south_west, color: t['sent'] == true ? C.ruby : C.emerald, size: 18),
              ),
              title: Text(t['sent'] == true ? 'To ${t['to_name'] ?? '—'}' : 'From ${t['from_name'] ?? 'Adda'}'),
              subtitle: Text('${'${t['created_at']}'.substring(0, 16).replaceAll('T', ' ')}${t['note'] != null && '${t['note']}'.isNotEmpty ? ' · ${t['note']}' : ''}', style: const TextStyle(color: C.mute, fontSize: 12)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if ((t['coins'] as num) != 0) CoinText('${t['sent'] == true ? '-' : '+'}${compact(t['coins'] as num)}', size: 13),
                if ((t['diamonds'] as num) != 0) CoinText('${t['sent'] == true ? '-' : '+'}${compact(t['diamonds'] as num)}', size: 13, diamond: true),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow();
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _Bal(label: 'Coins', child: ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => CoinText(grouped(c), size: 18)))),
        const SizedBox(width: 10),
        Expanded(child: _Bal(label: 'Diamonds', child: ValueListenableBuilder<int>(valueListenable: App.i.diamonds, builder: (_, d, __) => CoinText(grouped(d), size: 18, diamond: true)))),
      ]);
}

class _Bal extends StatelessWidget {
  const _Bal({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: C.mute, fontSize: 11)), const SizedBox(height: 4), child]),
      );
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});
  final Map<String, dynamic>? store;
  @override
  Widget build(BuildContext context) {
    final unlimited = store?['unlimited'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0E4A3A), Color(0xFF071F18)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.emerald.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.storefront, color: C.emerald),
          const SizedBox(width: 8),
          Text(unlimited ? 'ADMIN STORE' : 'MY AGENT STORE', style: const TextStyle(letterSpacing: 2, fontSize: 12, color: Colors.white70)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: CoinText(unlimited ? '∞ unlimited' : grouped(store?['coins'] as num? ?? 0), size: 22)),
          Expanded(child: CoinText(unlimited ? '∞ unlimited' : grouped(store?['diamonds'] as num? ?? 0), size: 22, diamond: true)),
        ]),
      ]),
    );
  }
}

// =====================================================================================
// Exchange: coins → diamonds, diamonds → coins
// =====================================================================================

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});
  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  Map<String, dynamic>? _info;
  final _toDia = TextEditingController(text: '1');
  final _toCoins = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _walletInfo().then((v) {
      if (mounted) setState(() => _info = v);
    }).catchError((_) {});
    App.i.refreshWallet();
  }

  @override
  void dispose() {
    _toDia.dispose();
    _toCoins.dispose();
    super.dispose();
  }

  Future<void> _run(String fn, Map<String, dynamic> args, String ok) async {
    setState(() => _busy = true);
    await attempt(context, () async {
      await App.i.rpc(fn, args);
      await App.i.refreshWallet();
    }, ok: ok);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final per = (_info?['coins_per_diamond'] as num?) ?? 2500000;
    final d2c = (_info?['diamond_to_coins'] as num?) ?? 1;
    final wantDia = int.tryParse(_toDia.text) ?? 0;
    final giveDia = int.tryParse(_toCoins.text) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Exchange')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _BalanceRow(),
        const Section('Coins → Diamonds'),
        _card(
          children: [
            Text('${grouped(per)} coins = 1 diamond', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(controller: _toDia, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Diamonds you want', prefixIcon: Icon(Icons.diamond, color: Color(0xFF7FB0FF)))),
            const SizedBox(height: 8),
            Text('Costs ${grouped(wantDia * per)} coins', style: const TextStyle(color: C.mute)),
            const SizedBox(height: 10),
            GoldButton(
              label: 'Get $wantDia diamond${wantDia == 1 ? '' : 's'}',
              icon: Icons.swap_vert,
              busy: _busy,
              onTap: _info?['coin_exchange_enabled'] == false || wantDia <= 0 ? null : () => _run('exchange_coins', {'p_diamonds': wantDia}, 'Exchanged'),
            ),
          ],
        ),
        const Section('Diamonds → Coins'),
        _card(
          children: [
            Text('1 diamond = ${grouped(d2c)} coin${d2c == 1 ? '' : 's'} · minimum 1,000 diamonds', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(controller: _toCoins, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Diamonds to exchange', prefixIcon: Icon(Icons.diamond, color: Color(0xFF7FB0FF)))),
            const SizedBox(height: 8),
            Text('You get ${grouped((giveDia * d2c).floor())} coins', style: const TextStyle(color: C.mute)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || giveDia < 1000 ? null : () => _run('exchange_diamonds', {'p_diamonds': giveDia}, 'Exchanged'),
              icon: const Icon(Icons.swap_vert, color: C.gold),
              label: const Text('Exchange to coins'),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

// =====================================================================================
// Custom amount: ask for any number of coins (or diamonds); price follows the packages
// =====================================================================================

Future<void> showCustomTopup(BuildContext context, List<Map<String, dynamic>> methods) async {
  final info = await _walletInfo().catchError((_) => <String, dynamic>{});
  if (!context.mounted) return;
  if (info['custom_topup_enabled'] == false) return toast(context, 'Custom amounts are not available right now');
  final order = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomSheet(info: info, methods: methods),
  );
  if (order == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => TopupOrderScreen(order: order)));
  await App.i.refreshWallet();
}

class _CustomSheet extends StatefulWidget {
  const _CustomSheet({required this.info, required this.methods});
  final Map<String, dynamic> info;
  final List<Map<String, dynamic>> methods;
  @override
  State<_CustomSheet> createState() => _CustomSheetState();
}

class _CustomSheetState extends State<_CustomSheet> {
  String _kind = 'coins';
  final _amount = TextEditingController();
  Map<String, dynamic>? _quote;
  String? _err;
  Timer? _t;
  bool _busy = false;

  @override
  void dispose() {
    _t?.cancel();
    _amount.dispose();
    super.dispose();
  }

  void _changed() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 400), _fetch);
  }

  Future<void> _fetch() async {
    final n = int.tryParse(_amount.text.replaceAll(',', ''));
    if (n == null || n <= 0) return setState(() => _quote = null);
    try {
      final q = Map<String, dynamic>.from(await App.i.rpc('custom_topup_quote', {'p_kind': _kind, 'p_amount': n}) as Map);
      if (mounted) setState(() {
        _quote = q;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _quote = null;
        _err = errText(e);
      });
    }
  }

  Future<void> _order(String method) async {
    final n = int.tryParse(_amount.text.replaceAll(',', ''));
    if (n == null) return;
    setState(() => _busy = true);
    try {
      final o = Map<String, dynamic>.from(await App.i.rpc('create_custom_topup', {'p_kind': _kind, 'p_amount': n, 'p_method': method}) as Map);
      if (mounted) Navigator.pop(context, o);
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final diamonds = widget.info['custom_diamonds_enabled'] != false;
    final q = _quote;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Buy a custom amount', style: serif(22)),
          const Text('Type exactly how much you want. The price uses the same rate as our packages.', style: TextStyle(color: C.mute, fontSize: 12)),
          const SizedBox(height: 12),
          if (diamonds)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'coins', label: Text('Coins'), icon: Icon(Icons.monetization_on)),
                ButtonSegment(value: 'diamonds', label: Text('Diamonds'), icon: Icon(Icons.diamond)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                setState(() => _kind = s.first);
                _fetch();
              },
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(labelText: _kind == 'coins' ? 'How many coins? (min ${grouped(widget.info['custom_min_coins'] as num? ?? 10000)})' : 'How many diamonds?'),
          ),
          const SizedBox(height: 10),
          if (q != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.gold2)),
              child: Row(children: [
                Expanded(child: Text('${grouped(q['amount'] as num)} ${q['kind']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                Text('৳${grouped(q['bdt'] as num)}', style: serif(22, color: C.gold)),
                Text('  ·  \$${q['usd']}', style: const TextStyle(color: C.mute)),
              ]),
            ),
          if (_err != null) Text(_err!, style: const TextStyle(color: C.ruby, fontSize: 12)),
          const SizedBox(height: 12),
          if (q != null) ...[
            const Text('Pay with', style: TextStyle(color: C.mute)),
            const SizedBox(height: 6),
            if (widget.methods.isEmpty) const Text('No payment method is available right now.', style: TextStyle(color: C.mute)),
            for (final m in widget.methods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _order(m['method'] as String),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: BorderSide(color: methodColors[m['method']] ?? C.gold)),
                  child: Text(methodNames[m['method']] ?? '${m['method']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}
