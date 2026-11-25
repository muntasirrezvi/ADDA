import 'package:flutter/material.dart';

import '../screens/room_screen.dart';
import '../services/active_room.dart';
import '../theme.dart';
import 'common.dart';

/// Floating bubble shown while a room is minimised. Drag it anywhere, tap to go back, × to leave.
class RoomBubble extends StatefulWidget {
  const RoomBubble({super.key, required this.navigator});
  final GlobalKey<NavigatorState> navigator;
  @override
  State<RoomBubble> createState() => _RoomBubbleState();
}

class _RoomBubbleState extends State<RoomBubble> with SingleTickerProviderStateMixin {
  Offset? _pos;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveRoom?>(
      valueListenable: ActiveRoom.current,
      builder: (context, room, _) => ValueListenableBuilder<bool>(
        valueListenable: ActiveRoom.screenOpen,
        builder: (context, open, _) {
          if (room == null || open) return const SizedBox.shrink();
          final size = MediaQuery.of(context).size;
          final pos = _pos ?? Offset(size.width - 92, size.height * .62);
          final r = room.room ?? const {};
          return Positioned(
            left: pos.dx,
            top: pos.dy,
            child: GestureDetector(
              onPanUpdate: (d) => setState(() {
                final p = (_pos ?? pos) + d.delta;
                _pos = Offset(p.dx.clamp(0.0, size.width - 80), p.dy.clamp(40.0, size.height - 120));
              }),
              onTap: () {
                widget.navigator.currentState?.push(MaterialPageRoute(builder: (_) => RoomScreen(roomId: room.id)));
              },
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(clipBehavior: Clip.none, children: [
                    RotationTransition(
                      turns: _spin,
                      child: Container(
                        width: 76,
                        height: 76,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: [C.gold, C.ruby, C.emerald, C.gold])),
                        child: ClipOval(child: CoverArt(imageUrl: r['cover_url'] as String?, template: '${r['cover_template'] ?? 'lantern'}', radius: 40, iconSize: 26)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 4,
                      bottom: -6,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: C.emerald, borderRadius: BorderRadius.circular(10)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.graphic_eq, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: GestureDetector(
                        onTap: () => room.leave(),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: Colors.black87, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
