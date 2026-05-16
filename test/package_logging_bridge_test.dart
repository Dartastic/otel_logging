// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:logging/logging.dart' as dart_logging;
import 'package:otel_logging/otel_logging.dart';
import 'package:test/test.dart';

/// In-memory log exporter, copied to keep this package independent
/// of the SDK's `test/testing_utils/`.
class _MemoryLogExporter implements LogRecordExporter {
  final List<ReadableLogRecord> records = [];
  bool _shutdown = false;

  void clear() => records.clear();

  @override
  Future<ExportResult> export(List<ReadableLogRecord> rs) async {
    if (_shutdown) return ExportResult.failure;
    records.addAll(rs);
    return ExportResult.success;
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

void main() {
  group('PackageLoggingBridge', () {
    late _MemoryLogExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemoryLogExporter();
      await OTel.initialize(
        serviceName: 'logging-bridge-test',
        detectPlatformResources: false,
        logRecordExporter: exporter,
      );
      // Replace the default OTLP processor with one that hits our
      // in-memory exporter so we can read what was emitted.
      OTel.loggerProvider().addLogRecordProcessor(
        SimpleLogRecordProcessor(exporter),
      );
      dart_logging.Logger.root.level = dart_logging.Level.ALL;
    });

    tearDown(() async {
      await PackageLoggingBridge.uninstall();
      await OTel.shutdown();
      await OTel.reset();
    });

    test('install routes Logger.fine() into OTel logs', () {
      PackageLoggingBridge.install();

      dart_logging.Logger('weather.api').fine('hello');

      final captured =
          exporter.records.where((r) => r.body == 'hello').toList();
      expect(captured, hasLength(1));
      expect(captured.single.severityNumber, equals(Severity.DEBUG));
    });

    test('logger name from package:logging becomes the OTel scope name', () {
      PackageLoggingBridge.install();

      dart_logging.Logger('com.example.module').info('scoped');

      final rec = exporter.records.firstWhere((r) => r.body == 'scoped');
      // Scope name lives on the LogRecord's instrumentation scope.
      expect(rec.instrumentationScope.name, equals('com.example.module'));
    });

    test('severity mapping matches DartLogBridge boundaries', () {
      PackageLoggingBridge.install();

      final l = dart_logging.Logger('sev');
      l.finest('finest'); //  300 → TRACE2
      l.finer('finer'); //    400 → TRACE2
      l.fine('fine'); //      500 → DEBUG
      l.config('config'); //  700 → DEBUG2
      l.info('info'); //      800 → INFO
      l.warning('warn'); //    900 → WARN
      l.severe('severe'); //  1000 → ERROR
      l.shout('shout'); //    1200 → FATAL

      Severity sev(String body) =>
          exporter.records.firstWhere((r) => r.body == body).severityNumber!;

      expect(sev('finest'), equals(Severity.TRACE2));
      expect(sev('finer'), equals(Severity.TRACE2));
      expect(sev('fine'), equals(Severity.DEBUG));
      expect(sev('config'), equals(Severity.DEBUG2));
      expect(sev('info'), equals(Severity.INFO));
      expect(sev('warn'), equals(Severity.WARN));
      expect(sev('severe'), equals(Severity.ERROR));
      expect(sev('shout'), equals(Severity.FATAL));
    });

    test('error and stackTrace surface as exception.* attributes', () {
      PackageLoggingBridge.install();

      StackTrace? trace;
      try {
        throw StateError('boom');
      } catch (_, s) {
        trace = s;
      }

      dart_logging.Logger('err').severe(
        'failed',
        StateError('boom'),
        trace,
      );

      final rec = exporter.records.firstWhere((r) => r.body == 'failed');
      final attrs = <String, Object>{
        for (final a in rec.attributes!.toList()) a.key: a.value,
      };

      expect(attrs['exception.type'], equals('StateError'));
      expect(attrs['exception.message'].toString(), contains('boom'));
      expect(attrs['exception.stacktrace'], isNotNull);
    });

    test('uninstall cancels the subscription — no further emits', () async {
      PackageLoggingBridge.install();

      dart_logging.Logger('before').info('pre');
      expect(exporter.records.any((r) => r.body == 'pre'), isTrue);
      exporter.clear();

      await PackageLoggingBridge.uninstall();

      dart_logging.Logger('after').info('post');
      expect(
        exporter.records.any((r) => r.body == 'post'),
        isFalse,
        reason: 'after uninstall the bridge must not emit anymore',
      );
      expect(PackageLoggingBridge.current, isNull);
    });

    test('install replaces an existing bridge', () {
      final first = PackageLoggingBridge.install();
      final second = PackageLoggingBridge.install();

      expect(first.isActive, isFalse, reason: 'first should be cancelled');
      expect(second.isActive, isTrue);
      expect(PackageLoggingBridge.current, same(second));
    });

    test('records below minimumSeverity are dropped', () {
      PackageLoggingBridge.install(minimumSeverity: Severity.WARN);

      dart_logging.Logger('a').fine('quiet'); // DEBUG — dropped
      dart_logging.Logger('a').warning('loud'); // WARN — kept

      expect(exporter.records.any((r) => r.body == 'quiet'), isFalse);
      expect(exporter.records.any((r) => r.body == 'loud'), isTrue);
    });
  });
}
