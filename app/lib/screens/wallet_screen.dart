import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'wallet_tools.dart';
import 'history_screen.dart';

const methodNames = {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'upay': 'Upay', 'bank': 'Bank transfer', 'usdt': 'USDT (TRC20)'};
const methodColors = {
  'bkash': Color(0xFFE2136E),
  'nagad': Color(0xFFF6921E),
  'rocket': Color(0xFF8C3494),
  'upay': Color(0xFF00A0E3),
  'bank': Color(0xFF2A9D7F),
  'usdt': Color(0xFF26A17B),
};

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  List<Map<String, dynamic>> _packs = [];
  List<Map<String, dynamic>> _methods = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await App.i.rpc('my_coin_packs');
      _packs = List<Map<String, dynamic>>.from(p as List);
      final m = await App.i.rpc('topup_methods');
      _methods = List<Map<String, dynamic>>.from(m as List);
      await App.i.refreshWallet();
    } catch (e) {
      if (mounted) toast(context, errText(e), bad: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _choose(Map<String, dynamic> pack) {
    final card = App.i.flag('pay_sslcommerz_enabled');
    final play = App.i.flag('pay_play_enabled') && Platform.isAndroid && pack['play_product_id'] != null;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${grouped(pack['coins'] as num)} coins', style: serif(22), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              '৳${grouped(pack['pay_bdt'] as num)}  ·  \$${pack['usd']}${(pack['discount_pct'] as num) > 0 ? '  ·  ${pack['discount_pct']}% off' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.mute),
            ),
            const SizedBox(height: 14),
            if (_methods.isEmpty && !card && !play) const EmptyState('Top-up is not available right now. Please try again later.', icon: Icons.schedule),
            for (final m in _methods)
              _MethodTile(
                name: methodNames[m['method']] ?? '${m['method']}',
                sub: 'Pay a verified Adda agent · coins in minutes',
                color: methodColors[m['method']] ?? C.gold,
                onTap: () {
                  Navigator.pop(ctx);
                  _agentOrder(pack, m['method'] as String);
                },
              ),
            if (card)
              _MethodTile(name: 'Card, bKash or Nagad checkout', sub: 'Visa, Mastercard and mobile banking via SSLCommerz', color: const Color(0xFF1F5FA8), onTap: () {
                Navigator.pop(ctx);
                _sslcommerz(pack);
              }),
            if (play)
              _MethodTile(name: 'Google Play', sub: 'Pay with your Play account', color: const Color(0xFF34A853), onTap: () {
                Navigator.pop(ctx);
                _googlePlay(pack);
              }),
          ]),
        ),
      ),
    );
  }

  Future<void> _agentOrder(Map<String, dynamic> pack, String method) async {
    await attempt(context, () async {
      final o = Map<String, dynamic>.from(await App.i.rpc('create_topup_order', {'p_pack': pack['id'], 'p_method': method}) as Map);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TopupOrderScreen(order: o)));
      await App.i.refreshWallet();
    });
  }

  Future<void> _sslcommerz(Map<String, dynamic> pack) async {
    await attempt(context, () async {
      final r = Map<String, dynamic>.from(await App.i.fn('pay-create', {'pack': pack['id']}) as Map);
      if (!mounted) return;
      final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PayWebView(url: r['url'] as String)));
      await App.i.refreshWallet();
      if (!mounted) return;
      if (result == 'paid') toast(context, 'Payment successful. Coins added.');
      if (result == 'failed') toast(context, 'Payment failed. No coins were added.', bad: true);
      if (result == 'review' || result == 'pending') toast(context, 'Payment is being confirmed. Coins will arrive shortly.');
    });
  }

  Future<void> _googlePlay(Map<String, dynamic> pack) async {
    await attempt(context, () => PlayBilling.i.buy(pack['play_product_id'] as String));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet'), actions: [
        IconButton(
          tooltip: 'History',
          icon: const Icon(Icons.receipt_long),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
        ),
      ]),
      body: RefreshIndicator(
        color: C.gold,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF3A2A12), Color(0xFF15100A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: C.gold2.withValues(alpha: .5)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('COINS', style: TextStyle(color: C.mute, letterSpacing: 2, fontSize: 11)),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<int>(valueListenable: App.i.coins, builder: (_, c, __) => FittedBox(child: CoinText(grouped(c), size: 26))),
                  const Text('For gifts, games and rooms', style: TextStyle(color: C.mute, fontSize: 11)),
                ]),
              ),
              Container(width: 1, height: 54, color: C.line),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('DIAMONDS', style: TextStyle(color: C.mute, letterSpacing: 2, fontSize: 11)),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<int>(valueListenable: App.i.diamonds, builder: (_, d, __) => FittedBox(child: CoinText(grouped(d), size: 26, diamond: true))),
                  const Text('Earned from gifts · send to friends', style: TextStyle(color: C.mute, fontSize: 11)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .86,
            children: [
              _Action(icon: Icons.tune, label: 'Custom\namount', color: const Color(0xFFE0A93A), onTap: () => showCustomTopup(context, _methods)),
              _Action(icon: Icons.swap_vert, label: 'Exchange', color: const Color(0xFF7FB0FF), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExchangeScreen()))),
              _Action(icon: Icons.send, label: 'Send to\nfriend', color: const Color(0xFF3DDC84), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendScreen()))),
              _Action(icon: Icons.receipt_long, label: 'History', color: const Color(0xFFE0485A), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
            ],
          ),
          const Section('Recharge coins'),
          const Text('Pick a package, pay a verified agent with bKash, Nagad or others, and coins arrive in minutes.', style: TextStyle(color: C.mute, fontSize: 12)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: C.gold)))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .82, mainAxisSpacing: 10, crossAxisSpacing: 10),
              itemCount: _packs.length,
              itemBuilder: (_, i) {
                final p = _packs[i];
                final off = (p['discount_pct'] as num).toInt();
                return GestureDetector(
                  onTap: () => _choose(p),
                  child: Container(
                    decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: off >= 10 ? C.gold2 : C.line)),
                    child: Stack(children: [
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.monetization_on, color: C.gold, size: 26 + i * 2.0),
                          const SizedBox(height: 6),
                          Text(compact(p['coins'] as num), style: serif(20, color: C.gold)),
                          const SizedBox(height: 2),
                          Text('৳${grouped(p['pay_bdt'] as num)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (off > 0) Text('৳${grouped(p['bdt'] as num)}', style: const TextStyle(color: C.mute, fontSize: 11, decoration: TextDecoration.lineThrough)),
                        ]),
                      ),
                      if (off > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: const BoxDecoration(color: C.ruby, borderRadius: BorderRadius.only(topRight: Radius.circular(15), bottomLeft: Radius.circular(10))),
                            child: Text('-$off%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ]),
                  ),
                );
              },
            ),
          const SizedBox(height: 14),
          const Text(
            'Your discount grows with your recharge tier and recent gifting, up to 20%. Coins are for gifts and features inside Adda and have no cash value.',
            style: TextStyle(color: C.mute, fontSize: 12),
          ),
        ]),
      ),
    );
  }

}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .16)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15)),
          ]),
        ),
      );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.name, required this.sub, required this.color, required this.onTap});
  final String name, sub;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: C.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(width: 10, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(color: C.mute, fontSize: 12)),
                ])),
                const Icon(Icons.chevron_right, color: C.mute),
              ]),
            ),
          ),
        ),
      );
}

/// Step 2 of an agent top-up: pay the shown number, then enter the transaction ID.
class TopupOrderScreen extends StatefulWidget {
  const TopupOrderScreen({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  State<TopupOrderScreen> createState() => _TopupOrderScreenState();
}

class _TopupOrderScreenState extends State<TopupOrderScreen> {
  final _sender = TextEditingController();
  final _trx = TextEditingController();
  XFile? _shot;
  bool _busy = false;
  String _status = 'awaiting_payment';
  String? _note;
  Timer? _tick;
  RealtimeChannel? _ch;
  Duration _left = Duration.zero;

  Map<String, dynamic> get o => widget.order;

  @override
  void initState() {
    super.initState();
    _status = (o['status'] as String?) ?? 'awaiting_payment';
    final exp = DateTime.tryParse('${o['expires_at']}');
    void upd() {
      if (exp == null) return;
      final l = exp.difference(DateTime.now());
      if (mounted) setState(() => _left = l.isNegative ? Duration.zero : l);
    }
    upd();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => upd());
    _ch = db
        .channel('topup:${o['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'topup_orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: o['id']),
          callback: (p) {
            if (!mounted) return;
            setState(() {
              _status = p.newRecord['status'] as String? ?? _status;
              _note = p.newRecord['note'] as String?;
            });
            if (_status == 'approved') App.i.refreshWallet();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_ch != null) db.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sender.text.trim().isEmpty || _trx.text.trim().length < 6) {
      return toast(context, 'Enter the number you paid from and the transaction ID', bad: true);
    }
    setState(() => _busy = true);
    await attempt(context, () async {
      String? proof;
      if (_shot != null) proof = await App.i.upload('payment-proofs', await _shot!.readAsBytes(), 'jpg', private: true);
      final r = await App.i.rpc('submit_topup_proof', {'p_order': o['id'], 'p_sender': _sender.text.trim(), 'p_trx': _trx.text.trim(), 'p_proof': proof});
      setState(() => _status = (r as Map)['status'] as String);
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final method = '${o['method']}';
    final name = methodNames[method] ?? method;
    final color = methodColors[method] ?? C.gold;
    final amount = '${o['currency'] == 'USD' ? '\$' : '৳'}${o['amount']}';
    return Scaffold(
      appBar: AppBar(title: Text('$name top-up')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        if (_status == 'awaiting_payment') ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)), child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
                const Spacer(),
                Icon(Icons.timer, size: 16, color: _left.inMinutes < 5 ? C.ruby : C.mute),
                const SizedBox(width: 4),
                Text('${_left.inMinutes}:${(_left.inSeconds % 60).toString().padLeft(2, '0')}', style: TextStyle(color: _left.inMinutes < 5 ? C.ruby : C.mute, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 16),
              const Text('1. Send exactly', style: TextStyle(color: C.mute)),
              Text(amount, style: serif(34, color: C.gold)),
              const SizedBox(height: 12),
              Text('2. To this ${o['account_type'] ?? ''} $name ${method == 'usdt' ? 'address' : 'number'}', style: const TextStyle(color: C.mute)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: SelectableText('${o['pay_to']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1))),
                IconButton(
                  icon: const Icon(Icons.copy, color: C.gold),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${o['pay_to']}'));
                    toast(context, 'Copied');
                  },
                ),
              ]),
              if (o['account_name'] != null) Text('Name: ${o['account_name']}', style: const TextStyle(color: C.mute, fontSize: 12)),
              if (o['instructions'] != null) ...[
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.info_outline, size: 16, color: C.gold), const SizedBox(width: 6), Expanded(child: Text('${o['instructions']}', style: const TextStyle(fontSize: 13)))]),
              ],
              const SizedBox(height: 14),
              Text(o['kind'] == 'diamonds' ? 'You will get ${grouped(o['diamonds'] as num)} diamonds.' : 'You will get ${grouped(o['coins'] as num)} coins.', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
          const Section('3. Confirm your payment'),
          TextField(controller: _sender, keyboardType: method == 'usdt' ? TextInputType.text : TextInputType.phone, decoration: InputDecoration(labelText: method == 'usdt' ? 'Your wallet address' : 'Your $name number')),
          const SizedBox(height: 10),
          TextField(controller: _trx, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Transaction ID (TrxID)', hintText: 'From the payment SMS or app')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 80);
              if (x != null) setState(() => _shot = x);
            },
            icon: Icon(_shot == null ? Icons.add_photo_alternate : Icons.check_circle, color: _shot == null ? C.gold : C.emerald),
            label: Text(_shot == null ? 'Add payment screenshot (optional)' : 'Screenshot added', style: const TextStyle(color: C.text)),
          ),
          const SizedBox(height: 16),
          GoldButton(label: 'I have paid', icon: Icons.check, busy: _busy, onTap: _left == Duration.zero ? null : _submit),
          TextButton(
            onPressed: () async {
              await attempt(context, () => App.i.rpc('cancel_topup_order', {'p_order': o['id']}));
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Cancel this top-up', style: TextStyle(color: C.mute)),
          ),
          if (_left == Duration.zero) const Text('Time is up. If you already paid, contact support with your TrxID.', textAlign: TextAlign.center, style: TextStyle(color: C.ruby)),
        ] else
          _StatusCard(status: _status, note: _note, coins: (o['coins'] as num).toInt()),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.coins, this.note});
  final String status;
  final int coins;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = switch (status) {
      'approved' => (Icons.check_circle, C.emerald, 'Coins added', '${grouped(coins)} coins are in your wallet. Enjoy!'),
      'rejected' => (Icons.cancel, C.ruby, 'Not approved', note ?? 'The agent could not find this payment.'),
      'expired' => (Icons.timer_off, C.mute, 'Expired', 'This top-up timed out.'),
      'cancelled' => (Icons.close, C.mute, 'Cancelled', 'No payment was made.'),
      _ => (Icons.hourglass_top, C.gold, 'Checking your payment', 'The agent is checking your transaction. This usually takes a few minutes. You can leave this screen; we will notify you.'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 14),
        Text(title, style: serif(26)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(color: C.mute)),
        if (status == 'submitted') const Padding(padding: EdgeInsets.only(top: 24), child: CircularProgressIndicator(color: C.gold)),
      ]),
    );
  }
}

class TopupHistoryScreen extends StatelessWidget {
  const TopupHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top-up history')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: db.from('topup_orders').select().eq('user_id', myId!).order('created_at', ascending: false).limit(50),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
          final rows = snap.data!;
          if (rows.isEmpty) return const EmptyState('No top-ups yet', icon: Icons.receipt_long);
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final st = r['status'] as String;
              return ListTile(
                title: Text(r['kind'] == 'diamonds' ? '${grouped(r['diamonds'] as num)} diamonds' : '${grouped(r['coins'] as num)} coins'),
                subtitle: Text('${methodNames[r['method']] ?? r['method']} · ${r['currency'] == 'USD' ? '\$' : '৳'}${r['amount']} · ${'${r['created_at']}'.substring(0, 10)}'),
                trailing: Text(st.replaceAll('_', ' '), style: TextStyle(color: st == 'approved' ? C.emerald : st == 'rejected' ? C.ruby : C.mute, fontWeight: FontWeight.w700)),
                onTap: st == 'awaiting_payment' || st == 'submitted'
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => TopupOrderScreen(order: {
                          ...r,
                          'expires_at': DateTime.parse('${r['created_at']}').add(Duration(minutes: App.i.number('topup_order_minutes', 30).toInt())).toIso8601String(),
                        })))
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

/// SSLCommerz checkout page. Closes itself when the payment page sends the user back to the app.
class PayWebView extends StatefulWidget {
  const PayWebView({super.key, required this.url});
  final String url;
  @override
  State<PayWebView> createState() => _PayWebViewState();
}

class _PayWebViewState extends State<PayWebView> {
  late final WebViewController _c;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onNavigationRequest: (req) {
          if (req.url.startsWith('adda://')) {
            final result = Uri.parse(req.url).queryParameters['payment'] ?? 'pending';
            Navigator.pop(context, result);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Secure payment'),
          bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, color: C.gold)) : null,
        ),
        body: WebViewWidget(controller: _c),
      );
}

/// Google Play in-app purchases. The server checks every purchase with Google before adding coins.
class PlayBilling {
  PlayBilling._();
  static final PlayBilling i = PlayBilling._();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  void start() {
    _sub ??= InAppPurchase.instance.purchaseStream.listen(_onPurchases, onError: (_) {});
  }

  Future<void> buy(String productId) async {
    start();
    if (!await InAppPurchase.instance.isAvailable()) throw Exception('Google Play is not available on this device');
    final r = await InAppPurchase.instance.queryProductDetails({productId});
    if (r.productDetails.isEmpty) throw Exception('This pack is not available in Google Play yet');
    await InAppPurchase.instance.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: r.productDetails.first, applicationUserName: myId),
      autoConsume: false,
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          await App.i.fn('pay-google-verify', {'productId': p.productID, 'purchaseToken': p.verificationData.serverVerificationData});
          await App.i.refreshWallet();
        } catch (_) {
          // stays unconsumed; it is retried the next time the purchase stream delivers it
        }
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
      }
    }
  }
}
