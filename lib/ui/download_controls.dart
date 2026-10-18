import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/offline.dart';

/// Shows what is being saved on this device, with pause / resume and stop. Takes no space when nothing is downloading.
class DownloadControls extends StatelessWidget {
  const DownloadControls({super.key});

  @override
  Widget build(BuildContext context) {
    final off = context.watch<OfflineStore>();
    if (!off.busy) return const SizedBox.shrink();
    final total = off.batchTotal == 0 ? 1 : off.batchTotal;
    var part = 0.0;
    for (final v in off.progress.values) {
      part += v;
    }
    final fraction = ((off.batchDone + part) / total).clamp(0.0, 1.0);
    final n = (off.batchDone + 1).clamp(1, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(off.paused ? 'Downloads paused · $n of $total' : 'Downloading · $n of $total'),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: fraction),
          ]),
        ),
        IconButton(
          tooltip: off.paused ? 'Resume' : 'Pause',
          icon: Icon(off.paused ? Icons.play_arrow : Icons.pause),
          onPressed: off.paused ? off.resume : off.pause,
        ),
        IconButton(tooltip: 'Stop', icon: const Icon(Icons.stop), onPressed: off.stopAll),
      ]),
    );
  }
}
