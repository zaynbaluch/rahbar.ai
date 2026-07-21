import 'dart:convert';
import 'dart:io';

import 'package:bayaz_ai/core/storage/atomic_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bayaz-atomic-store-');
    file = File('${directory.path}/state.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('publishes complete JSON and leaves no temporary file', () async {
    await AtomicFileStore.shared.writeJson(file, {'value': 1});

    expect(jsonDecode(await file.readAsString()), {'value': 1});
    expect(
      await directory.list().where((entry) => entry.path.endsWith('.tmp')).isEmpty,
      isTrue,
    );
  });

  test('keeps the last of many queued writes', () async {
    await Future.wait([
      for (var value = 0; value < 100; value++)
        AtomicFileStore.shared.writeJson(file, {'value': value}),
    ]);

    expect(jsonDecode(await file.readAsString()), {'value': 99});
  });

  test('serializes full read modify write transactions', () async {
    await AtomicFileStore.shared.writeJson(file, <int>[]);

    Future<void> append(int value) => AtomicFileStore.shared.runExclusive(
          file.path,
          () async {
            final values = List<int>.from(jsonDecode(await file.readAsString()) as List);
            await Future<void>.delayed(Duration(milliseconds: value.isEven ? 2 : 1));
            values.add(value);
            await file.writeAsString(jsonEncode(values), flush: true);
          },
        );

    await Future.wait([for (var value = 0; value < 20; value++) append(value)]);
    final values = List<int>.from(jsonDecode(await file.readAsString()) as List);
    expect(values, List<int>.generate(20, (index) => index));
  });

  test('moves corrupt data out of the active path', () async {
    await file.writeAsString('{broken', flush: true);

    final moved = await AtomicFileStore.shared.quarantineCorrupt(file);

    expect(await file.exists(), isFalse);
    expect(moved, isNotNull);
    expect(await moved!.readAsString(), '{broken');
  });
}
