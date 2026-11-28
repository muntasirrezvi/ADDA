import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Every coin and diamond movement: purchases, gifts, games, transfers, rewards.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _Kind {
  const _Kind(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const _kinds = <String, _Kind>{
  'topup': _Kind('Recharge', Icons.add_card, Color(0xFFE0A93A)),
  'agent_buy': _Kind('Bought from agent', Icons.add_card, Color(0xFFE0A93A)),
  'admin_adjust': _Kind('From Adda', Icons.verified, Color(0xFF3DDC84)),
  'refund': _Kind('Refund', Icons.undo, Color(0xFF3DDC84)),
  'party_refund': _Kind('Game refund', Icons.undo, Color(0xFF3DDC84)),
  'donation_sent': _Kind('Reel tip sent', Icons.volunteer_activism, Color(0xFFFF6B8B)),
  'donation_received': _Kind('Reel tip received', Icons.volunteer_activism, Color(0xFF6BE675)),
  'theme': _Kind('Room theme', Icons.palette, Color(0xFF8A7BFF)),
  'payout': _Kind('Payout', Icons.account_balance, Color(0xFFFF8A80)),
  'gift_sent': _Kind('Gift sent', Icons.card_giftcard, Color(0xFFFF6B8B)),
  'gift_received': _Kind('Gift received', Icons.redeem, Color(0xFF6BE675)),
  'game_bet': _Kind('Game bet', Icons.sports_esports, Color(0xFF8A7BFF)),
  'game_win': _Kind('Game win', Icons.emoji_events, Color(0xFFFFD54F)),
  'game_chest': _Kind('Game chest', Icons.inventory_2, Color(0xFFFFB347)),
  'transfer_in': _Kind('Received', Icons.call_received, Color(0xFF3DDC84)),
  'transfer_out': _Kind('Sent', Icons.call_made, Color(0xFF7FB0FF)),
  'store_transfer': _Kind('Store transfer', Icons.storefront, Color(0xFF3DDC84)),
  'exchange': _Kind('Exchange', Icons.swap_vert, Color(0xFF7FB0FF)),
  'reward': _Kind('Daily reward', Icons.calendar_month, Color(0xFFFFB347)),
  'luckybag_send': _Kind('Lucky bag sent', Icons.shopping_bag, Color(0xFFE0485A)),
  'luckybag_grab': _Kind('Lucky bag', Icons.shopping_bag, Color(0xFF6BE675)),
  'luckybag_return': _Kind('Lucky bag returned', Icons.shopping_bag, Color(0xFF6BE675)),
  'party_stake': _Kind('Game stake', Icons.casino, Color(0xFF8A7BFF)),
  'party_win': _Kind('Game win', Icons.casino, Color(0xFFFFD54F)),
  'admin_grant': _Kind('From Adda', Icons.verified, Color(0xFF3DDC84)),
  'welcome': _Kind('Welcome bonus', Icons.celebration, Color(0xFFFFB347)),
  'reel_donation': _Kind('Reel tip', Icons.volunteer_activism, Color(0xFFFF6B8B)),
};

const _gameNames = {
  'greedy': 'Greedy',
  'fruit': 'Fruit Party',
  'slots777': 'Lucky 777',
  'crash': 'Rocket',
  'sicbo': 'Dice',
  'bigsix': 'Lucky Wheel',
  'mines': 'Gems',
};

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _rows = <Map<String, dynamic>>[];
  final _orders = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrders();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final from = _rows.length;
      final r = await db.from('transactions').select().eq('user_id', myId!).order('id', ascending: false).range(from, from + 59);
      final list = List<Map<String, dynamic>>.from(r);
      if (!mounted) return;
      setState(() {
        _rows.addAll(list);
        _more = list.length == 60;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, errText(e), bad: true);
      }
    }
  }

  Future<void> _loadOrders() async {
    try {
      final r = await db.from('topup_orders').select().eq('user_id', myId!).order('created_at', ascending: false).limit(100);
      if (mounted) setState(() => _orders.addAll(List<Map<String, dynamic>>.from(r)));
    } catch (_) {}
  }

  String _title(Map<String, dynamic> t) {
    final k = '${t['kind']}';
    final base = _kinds[k]?.label ?? k.replaceAll('_', ' ');
    final ref = '${t['ref'] ?? ''}';
    if (k.startsWith('game') && _gameNames[ref] != null) return '$base · ${_gameNames[ref]}';
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final coins = _rows.where((t) => (t['coins'] as num? ?? 0) != 0).toList();
    final diamonds = _rows.where((t) => (t['diamonds'] as num? ?? 0) != 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: C.gold,
          labelColor: C.gold,
          unselectedLabelColor: C.mute,
          tabs: const [Tab(text: 'All'), Tab(text: 'Coins'), Tab(text: 'Diamonds'), Tab(text: 'Purchases')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.gold))
          : TabBarView(controller: _tabs, children: [
              _list(_rows),
              _list(coins),
              _list(diamonds),
              _purchases(),
            ]),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const EmptyState('Nothing here yet', icon: Icons.receipt_long);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_more && !_loading && n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
          _more = false;
          _load();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: C.line),
        itemBuilder: (_, i) {
          final t = rows[i];
          final kind = _kinds['${t['kind']}'] ?? const _Kind('Other', Icons.swap_horiz, C.mute);
          final c = (t['coins'] as num? ?? 0).toInt();
          final d = (t['diamonds'] as num? ?? 0).toInt();
          final at = DateTime.tryParse('${t['created_at']}')?.toLocal();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: kind.color.withValues(alpha: .15), shape: BoxShape.circle),
                child: Icon(kind.icon, color: kind.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (at != null) Text(_when(at), style: const TextStyle(color: C.mute, fontSize: 11)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (c != 0) _amount(c, false),
                if (d != 0) _amount(d, true),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _amount(int v, bool diamond) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${v > 0 ? '+' : '−'}${grouped(v.abs())}', style: TextStyle(color: v > 0 ? const Color(0xFF6BE675) : const Color(0xFFFF8A80), fontWeight: FontWeight.w800)),
        const SizedBox(width: 4),
        Icon(diamond ? Icons.diamond : Icons.monetization_on, size: 14, color: diamond ? const Color(0xFF7FDBFF) : C.gold),
      ]);

  Widget _purchases() {
    if (_orders.isEmpty) return const EmptyState('No purchases yet', icon: Icons.add_card);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: C.line),
      itemBuilder: (_, i) {
        final o = _orders[i];
        final status = '${o['status'] ?? ''}';
        final at = DateTime.tryParse('${o['created_at']}')?.toLocal();
        final coins = (o['coins'] as num? ?? 0).toInt();
        final dia = (o['diamonds'] as num? ?? 0).toInt();
        final color = status == 'approved' ? const Color(0xFF6BE675) : (status == 'rejected' || status == 'expired' ? const Color(0xFFFF8A80) : C.gold);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            const CircleAvatar(radius: 20, backgroundColor: Color(0x22E0A93A), child: Icon(Icons.add_card, color: Color(0xFFE0A93A), size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dia > 0 ? '${grouped(dia)} diamonds' : '${grouped(coins)} coins', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${o['method'] ?? ''}${at != null ? ' · ${_when(at)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.mute, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (o['amount'] != null) Text('${o['currency'] == 'BDT' || o['currency'] == null ? '৳' : '${o['currency']} '}${o['amount']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        );
      },
    );
  }

  String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.day}/${t.month}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}
