import 'dart:io';

import 'package:celechron/database/hive_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('hive_paths_test_');
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  group('shouldMigrateFile', () {
    test('includes .hive main data files', () {
      expect(HivePaths.shouldMigrateFile('dboptions.hive'), isTrue);
      expect(HivePaths.shouldMigrateFile('dbuser.hive'), isTrue);
      expect(HivePaths.shouldMigrateFile('dbflow.hive'), isTrue);
    });
    test('includes Hive write-ahead logs', () {
      expect(HivePaths.shouldMigrateFile('dboptions.hive.log'), isTrue);
    });
    test('excludes runtime lock files', () {
      expect(HivePaths.shouldMigrateFile('dboptions.hive.lock'), isFalse);
      expect(HivePaths.shouldMigrateFile('dboptions.lock'), isFalse);
      expect(HivePaths.shouldMigrateFile('dboptions.lock~'), isFalse);
    });
    test('excludes unrelated files', () {
      expect(HivePaths.shouldMigrateFile('random.txt'), isFalse);
      expect(HivePaths.shouldMigrateFile('banner.png'), isFalse);
    });
    test('case-insensitive', () {
      expect(HivePaths.shouldMigrateFile('DBOPTIONS.HIVE'), isTrue);
      expect(HivePaths.shouldMigrateFile('DBOPTIONS.HIVE.LOCK'), isFalse);
    });
  });

  group('migrateFiles', () {
    test('copies eligible Hive files from old to new', () async {
      final oldRoot = Directory('${sandbox.path}/old')..createSync();
      final newRoot = Directory('${sandbox.path}/new')..createSync();
      File('${oldRoot.path}/dboptions.hive').writeAsStringSync('options-data');
      File('${oldRoot.path}/dbuser.hive').writeAsStringSync('user-data');
      File('${oldRoot.path}/dbflow.hive').writeAsStringSync('flow-data');
      File('${oldRoot.path}/dboptions.hive.lock').writeAsStringSync('lock-payload');

      final copied =
          await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      expect(copied, 3);
      expect(File('${newRoot.path}/dboptions.hive').existsSync(), isTrue);
      expect(
        File('${newRoot.path}/dboptions.hive').readAsStringSync(),
        'options-data',
      );
      expect(File('${newRoot.path}/dbuser.hive').existsSync(), isTrue);
      expect(File('${newRoot.path}/dbflow.hive').existsSync(), isTrue);
      // Lock file NOT copied
      expect(
        File('${newRoot.path}/dboptions.hive.lock').existsSync(),
        isFalse,
      );
      // Marker written
      final marker = File('${newRoot.path}/${HivePaths.pivotMarkerFileName}');
      expect(marker.existsSync(), isTrue);
      expect(marker.readAsStringSync(), contains('celechron pivot v1'));
    });

    test('is idempotent: marker present => skip', () async {
      final oldRoot = Directory('${sandbox.path}/old')..createSync();
      final newRoot = Directory('${sandbox.path}/new')..createSync();
      File('${oldRoot.path}/dboptions.hive').writeAsStringSync('data');
      // Pre-create the marker (simulating a previous successful run)
      File('${newRoot.path}/${HivePaths.pivotMarkerFileName}')
          .writeAsStringSync('already done\n');

      final copied =
          await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      expect(copied, 0);
      expect(File('${newRoot.path}/dboptions.hive').existsSync(), isFalse);
    });

    test('does not overwrite existing target', () async {
      final oldRoot = Directory('${sandbox.path}/old')..createSync();
      final newRoot = Directory('${sandbox.path}/new')..createSync();
      File('${oldRoot.path}/dboptions.hive').writeAsStringSync('OLD-options-data');
      File('${newRoot.path}/dboptions.hive').writeAsStringSync('NEW-options-data');

      await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      expect(
        File('${newRoot.path}/dboptions.hive').readAsStringSync(),
        'NEW-options-data',
      );
    });

    test('no old data: still writes marker, copies 0', () async {
      // oldRoot does NOT exist on disk
      final oldRoot = Directory('${sandbox.path}/nonexistent');
      final newRoot = Directory('${sandbox.path}/new')..createSync();

      final copied =
          await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      expect(copied, 0);
      expect(
        File('${newRoot.path}/${HivePaths.pivotMarkerFileName}').existsSync(),
        isTrue,
      );
    });

    test('same path (case-insensitive): skips immediately', () async {
      final dir = Directory('${sandbox.path}/SamePath')..createSync();
      File('${dir.path}/dboptions.hive').writeAsStringSync('data');

      // Pass the same path twice -- should not duplicate or break
      final copied =
          await HivePaths.migrateFiles(oldRoot: dir, newRoot: dir);

      expect(copied, 0);
      expect(
        File('${dir.path}/${HivePaths.pivotMarkerFileName}').existsSync(),
        isTrue,
      );
    });

    test('skips non-Hive files in old root', () async {
      final oldRoot = Directory('${sandbox.path}/old')..createSync();
      final newRoot = Directory('${sandbox.path}/new')..createSync();
      File('${oldRoot.path}/dboptions.hive').writeAsStringSync('hive-data');
      File('${oldRoot.path}/README.txt').writeAsStringSync('readme');
      File('${oldRoot.path}/banner.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final copied =
          await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      expect(copied, 1);
      expect(File('${newRoot.path}/dboptions.hive').existsSync(), isTrue);
      expect(File('${newRoot.path}/README.txt').existsSync(), isFalse);
      expect(File('${newRoot.path}/banner.png').existsSync(), isFalse);
    });

    test('partial failure: keeps going, still writes marker', () async {
      final oldRoot = Directory('${sandbox.path}/old')..createSync();
      final newRoot = Directory('${sandbox.path}/new')..createSync();
      // Mark one file unreadable by making it a directory instead
      Directory('${oldRoot.path}/dbbroken.hive').createSync();
      File('${oldRoot.path}/dboptions.hive').writeAsStringSync('data');

      final result =
          await HivePaths.migrateFiles(oldRoot: oldRoot, newRoot: newRoot);

      // dboptions.hive copies fine; dbbroken.hive fails (dir not file), doesn't count.
      expect(result, 1);
      expect(File('${newRoot.path}/dboptions.hive').existsSync(), isTrue);
      expect(
        File('${newRoot.path}/${HivePaths.pivotMarkerFileName}').existsSync(),
        isTrue,
      );
    });
  });
}