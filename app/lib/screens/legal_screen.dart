import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// In-app Privacy Policy / Terms of Service. The text is bundled (assets/brand/legal.json),
/// the same file the public web page uses, so it works offline too.
class LegalScreen extends StatelessWidget {
  final bool terms;
  const LegalScreen({super.key, this.terms = false});

  static void open(BuildContext context, {bool terms = false}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen(terms: terms)));

  static const webBase = 'https://muntasirrezvi.github.io/ADDA/';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(terms ? 'Terms of Service' : 'Privacy Policy'),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchUrl(Uri.parse('$webBase${terms ? 'terms' : 'privacy'}/'), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('assets/brand/legal.json'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
          final all = jsonDecode(snap.data!) as Map<String, dynamic>;
          final doc = all[terms ? 'terms' : 'privacy'] as Map<String, dynamic>;
          final sections = (doc['sections'] as List).cast<List>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Row(children: [
                Image.asset('assets/brand/logo_icon.webp', width: 44, height: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doc['title'] as String, style: serif(22)),
                    Text('Last updated ${all['updated']}', style: const TextStyle(color: C.mute, fontSize: 12)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Text(doc['intro'] as String, style: const TextStyle(height: 1.5)),
              for (final s in sections) ...[
                const SizedBox(height: 18),
                Text(s[0] as String, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(s[1] as String, style: const TextStyle(height: 1.5, color: C.text)),
              ],
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LegalScreen(terms: !terms))),
                  child: Text(terms ? 'Read the Privacy Policy' : 'Read the Terms of Service', style: const TextStyle(color: C.gold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
