import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

const _methodNames = {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': 'Bank', 'payoneer': 'Payoneer'};

/// Diamonds (earned from gifts) → real money. The rules come from the admin console.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic>? _st;
  List<Map<String, dynamic>> _history = [];
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _holder = TextEditingController();
  String? _method;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = Map<String, dynamic>.from(await App.i.rpc('withdraw_status') as Map);
      final h = await db.from('payouts').select().eq('user_id', myId!).order('created_at', ascending: false).limit(30);
      await App.i.refreshWallet();
      if (!mounted) return;
      setState(() {
        _st = st;
        _history = List<Map<String, dynamic>>.from(h);
        final methods = List<String>.from(st['methods'] as List);
        _method ??= methods.isEmpty ? null : methods.first;
        if (_amount.text.isEmpty) _amount.text = '${st['diamonds']}';
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
  }

  num get _perUsd => (_st?['diamonds_per_usd'] as num?) ?? 625000;
  num get _bdt => (_st?['usd_to_bdt'] as num?) ?? 120;
  num get _fee => (_st?['fee_pct'] as num?) ?? 0;

  ({double usd, double fee, double bdt}) _quote(int d) {
    final gross = d / _perUsd;
    final fee = gross * _fee / 100;
    return (usd: gross - fee, fee: fee, bdt: (gross - fee) * _bdt);
  }

  Future<void> _submit() async {
    final d = int.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
    if (_method == null) return toast(context, 'Choose how to get paid', bad: true);
    if (_account.text.trim().isEmpty) return toast(context, 'Enter your ${_methodNames[_method] ?? _method} number', bad: true);
    final q = _quote(d);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm withdrawal', style: serif(20)),
        content: Text('${grouped(d)} diamonds\n→ ৳${q.bdt.toStringAsFixed(0)} (≈ \$${q.usd.toStringAsFixed(2)})\n\nTo ${_methodNames[_method]}: ${_account.text.trim()}'
            '${_holder.text.trim().isEmpty ? '' : '\nName: ${_holder.text.trim()}'}\n\nThe diamonds are held until our team pays you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: C.mute))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw', style: TextStyle(color: C.gold))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await attempt(context, () async {
      await App.i.rpc('request_withdrawal', {'p_diamonds': d, 'p_method': _method, 'p_account': _account.text.trim(), 'p_name': _holder.text.trim()});
      _amount.clear();
      await _load();
    }, ok: 'Request sent. You will get a notification when it is paid.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null) return Scaffold(appBar: AppBar(title: const Text('Diamonds & withdraw')), body: const Center(child: CircularProgressIndicator(color: C.gold)));
    final checks = List<Map<String, dynamic>>.from((st['checks'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final can = st['can'] == true;
    final balance = (st['diamonds'] as num).toInt();
    final min = (st['min'] as num).toInt();
    final dailyMax = (st['daily_max'] as num).toInt();
    final used = (st['used_today'] as num).toInt();
    final d = int.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
    final q = _quote(d);
    final all = _quote(balance);
    final methods = List<String>.from(st['methods'] as List);
    return Scaffold(
      appBar: AppBar(title: const Text('Diamonds & withdraw')),
      body: RefreshIndicator(
        color: C.gold,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1E3A6E), Color(0xFF0E1A34)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF5A8AFF).withValues(alpha: .4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('MY DIAMONDS', style: TextStyle(color: Colors.white60, letterSpacing: 2, fontSize: 11)),
                  const SizedBox(height: 6),
                  CoinText(grouped(balance), size: 28, diamond: true),
                  const SizedBox(height: 4),
                  Text('≈ ৳${all.bdt.toStringAsFixed(0)}  ·  \$${all.usd.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70)),
                ]),
              ),
              Image.asset('assets/games/gem_sapphire.webp', width: 70),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Diamonds come from gifts people send you. Coins you buy or win cannot be withdrawn.', style: TextStyle(color: C.mute, fontSize: 11)),
          const Section('Requirements'),
          Container(
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Column(children: [
              for (final c in checks)
                ListTile(
                  dense: true,
                  leading: Icon(c['ok'] == true ? Icons.check_circle : Icons.cancel, color: c['ok'] == true ? C.emerald : C.ruby),
                  title: Text('${c['label']}'),
                  subtitle: c['ok'] != true && c['detail'] != null ? Text('${c['detail']}', style: const TextStyle(color: C.mute, fontSize: 11)) : null,
                  trailing: c['key'] == 'verified' && c['ok'] != true
                      ? TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyScreen())).then((_) => _load()), child: const Text('Verify', style: TextStyle(color: C.gold)))
                      : null,
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.today, color: C.gold),
                title: Text('Daily limit ${compact(dailyMax)} diamonds'),
                subtitle: Text('${compact(used)} used today', style: const TextStyle(color: C.mute, fontSize: 11)),
              ),
            ]),
          ),
          const Section('Withdraw'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Diamonds (minimum ${grouped(min)})', suffixIcon: const Icon(Icons.diamond, color: Color(0xFF7FB0FF))),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final p in [('Min', min), ('Half', balance ~/ 2), ('All', balance)])
              ActionChip(label: Text(p.$1), onPressed: () => setState(() => _amount.text = '${p.$2}')),
          ]),
          const SizedBox(height: 8),
          Text(
            d > 0 ? 'You receive ৳${q.bdt.toStringAsFixed(0)}  (≈ \$${q.usd.toStringAsFixed(2)})${_fee > 0 ? ' after a $_fee% fee' : ''}' : '',
            style: const TextStyle(color: C.gold, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text('Get paid by', style: TextStyle(color: C.mute)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final m in methods) ChoiceChip(label: Text(_methodNames[m] ?? m), selected: _method == m, selectedColor: C.gold, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _account,
            keyboardType: _method == 'bank' ? TextInputType.text : TextInputType.phone,
            decoration: InputDecoration(labelText: _method == 'bank' ? 'Bank, branch and account number' : '${_methodNames[_method] ?? 'Account'} number'),
          ),
          TextField(controller: _holder, decoration: const InputDecoration(labelText: 'Account holder name')),
          const SizedBox(height: 16),
          GoldButton(label: can ? 'Request withdrawal' : 'Complete the requirements first', icon: Icons.account_balance_wallet, busy: _busy, onTap: can && d >= min && d <= balance ? _submit : null),
          const Section('History'),
          if (_history.isEmpty) const EmptyState('No withdrawals yet', icon: Icons.account_balance),
          for (final p in _history)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['amount_bdt'] != null ? '৳${(p['amount_bdt'] as num).toStringAsFixed(0)} · ${_methodNames[p['method']] ?? p['method']}' : '\$${p['amount_usd']} · ${p['method']}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${grouped(p['diamonds'] as num)} diamonds · ${'${p['created_at']}'.substring(0, 10)}', style: const TextStyle(color: C.mute, fontSize: 12)),
                    if (p['paid_ref'] != null) Text('Ref ${p['paid_ref']}', style: const TextStyle(color: C.mute, fontSize: 12)),
                    if (p['note'] != null) Text('${p['note']}', style: const TextStyle(color: C.mute, fontSize: 12)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (p['status'] == 'paid' ? C.emerald : p['status'] == 'rejected' ? C.ruby : C.gold).withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${p['status']}', style: TextStyle(color: p['status'] == 'paid' ? C.emerald : p['status'] == 'rejected' ? C.ruby : C.gold, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
