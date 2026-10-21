import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/edith_theme.dart';

/// "Cogitating…", "Musing…" and friends: a small spinner and a word that
/// changes every second or so while EDITH is working on a reply.
class ThinkingWords extends StatefulWidget {
  const ThinkingWords({super.key});

  @override
  State<ThinkingWords> createState() => _ThinkingWordsState();
}

class _ThinkingWordsState extends State<ThinkingWords> {
  static const _words = [
    'Cogitating', 'Musing', 'Pondering', 'Computing', 'Calculating',
    'Deliberating', 'Analysing', 'Reasoning', 'Connecting dots',
    'Synthesising', 'Scheming', 'Mulling', 'Processing', 'Working on it',
    'Crunching', 'Decoding', 'Strategising', 'Contemplating',
  ];

  final _rng = Random();
  late int _i;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _i = _rng.nextInt(_words.length);
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1 + _rng.nextInt(3)) % _words.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: EdithTheme.electricBlue,
          ),
        ),
        const SizedBox(width: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            '${_words[_i]}…',
            key: ValueKey(_i),
            style: const TextStyle(
                color: EdithTheme.textSecondary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
