import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';
import 'absorb_plus_logo.dart';

/// The "Absorbing" tab icon: the drop, moving while something is playing.
/// Colors follow the old wave icon: primary when the tab is selected,
/// onSurfaceVariant when not, and the nav bar's icon theme in e-ink mode
/// (where the selected pill is solid black and the icon must turn white).
class AbsorbingNavIcon extends StatefulWidget {
  final double size;
  final bool active;

  const AbsorbingNavIcon({super.key, this.size = 24, required this.active});

  @override
  State<AbsorbingNavIcon> createState() => _AbsorbingNavIconState();
}

class _AbsorbingNavIconState extends State<AbsorbingNavIcon> {
  final _player = AudioPlayerService();
  late bool _playing = _player.isPlaying;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final playing = _player.isPlaying;
    // The player notifies for much more than play/pause; rebuild only on that.
    if (playing != _playing && mounted) setState(() => _playing = playing);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final einkColor = PlayerSettings.einkMode
        ? IconTheme.of(context).color
        : null;
    return AnimatedAbsorbDrop(
      size: widget.size,
      animating: _playing,
      color: einkColor ?? (widget.active ? cs.primary : cs.onSurfaceVariant),
    );
  }
}
