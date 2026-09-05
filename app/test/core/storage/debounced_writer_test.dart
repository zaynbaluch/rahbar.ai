import 'dart:async';

import 'package:bayaz_ai/core/storage/debounced_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces rapid scheduled values', () async {
    final saved = <int>[];
    final writer = DebouncedWriter<int>(
      delay: const Duration(milliseconds: 5),
      save: (value) async => saved.add(value),
    );

    writer.schedule(1);
    writer.schedule(2);
    writer.schedule(3);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await writer.settle();

    expect(saved, [3]);
    writer.dispose();
  });

  test('flush publishes the current snapshot after queued work', () async {
    final gate = Completer<void>();
    final saved = <int>[];
    final writer = DebouncedWriter<int>(
      delay: const Duration(milliseconds: 1),
      save: (value) async {
        if (value == 1) await gate.future;
        saved.add(value);
      },
    );

    writer.schedule(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final flushed = writer.flush(2);
    gate.complete();
    await flushed;

    expect(saved, [1, 2]);
    writer.dispose();
  });

  test('flush replaces a pending debounce value', () async {
    final saved = <int>[];
    final writer = DebouncedWriter<int>(
      delay: const Duration(seconds: 1),
      save: (value) async => saved.add(value),
    );

    writer.schedule(1);
    await writer.flush(2);

    expect(saved, [2]);
    writer.dispose();
  });
}
