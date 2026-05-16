// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:logging/logging.dart' as dart_logging;

/// Bridges `package:logging` records into the OpenTelemetry logs SDK.
///
/// `package:logging` is the de-facto-standard Dart logging package — every
/// Dart server framework and most Flutter apps emit through it. Once
/// [install] has been called against an OTel [LoggerProvider], every
/// `Logger(...).fine/info/warning/severe(...)` call also flows through
/// the OTel logs pipeline and inherits trace_id / span_id from
/// `Context.current` for free.
///
/// Example:
///
/// ```dart
/// await OTel.initialize(serviceName: 'my-app');
/// PackageLoggingBridge.install();
/// // ... your application code ...
/// // Later, before exit:
/// await PackageLoggingBridge.uninstall();
/// await OTel.shutdown();
/// ```
///
/// **Lifecycle / hang note.** The bridge attaches a `StreamSubscription`
/// to `dart_logging.Logger.root.onRecord`. Like any open subscription,
/// it keeps the Dart isolate alive after `main()` returns. Always call
/// [uninstall] before letting `main()` end; doing so before
/// [OTel.shutdown] is the safest order.
class PackageLoggingBridge {
  PackageLoggingBridge._({
    required LoggerProvider provider,
    required String defaultLoggerName,
    required Severity minimumSeverity,
  })  : _provider = provider,
        _defaultLoggerName = defaultLoggerName,
        _minimumSeverity = minimumSeverity;

  final LoggerProvider _provider;
  final String _defaultLoggerName;
  final Severity _minimumSeverity;

  StreamSubscription<dart_logging.LogRecord>? _subscription;

  static PackageLoggingBridge? _instance;

  /// Returns the currently-installed bridge, or null if none is installed.
  static PackageLoggingBridge? get current => _instance;

  /// Installs the bridge. After this returns, every record emitted by
  /// any `package:logging` `Logger` flows through OTel logs.
  ///
  /// [loggerProvider] — defaults to `OTel.loggerProvider()`. Pass a
  /// custom one if you've configured a named logger provider with a
  /// different exporter.
  ///
  /// [defaultLoggerName] — used when the `package:logging` `Logger` has
  /// an empty `name` (i.e. records from `Logger.root` directly). Each
  /// `Logger('com.example.foo')` is mapped to its own OTel
  /// instrumentation scope (`'com.example.foo'`).
  ///
  /// [minimumSeverity] — records below this are dropped. Defaults to
  /// `TRACE` so the bridge never silently filters; tune
  /// `dart_logging.Logger.root.level` to control what `package:logging`
  /// itself emits.
  ///
  /// Calling [install] when a bridge is already installed replaces it.
  static PackageLoggingBridge install({
    LoggerProvider? loggerProvider,
    String defaultLoggerName = 'package.logging',
    Severity minimumSeverity = Severity.TRACE,
  }) {
    _instance?._cancel();
    final provider = loggerProvider ?? OTel.loggerProvider();
    final bridge = PackageLoggingBridge._(
      provider: provider,
      defaultLoggerName: defaultLoggerName,
      minimumSeverity: minimumSeverity,
    );
    bridge._subscription =
        dart_logging.Logger.root.onRecord.listen(bridge._onRecord);
    _instance = bridge;
    return bridge;
  }

  /// Uninstalls the current bridge if any. Cancels the underlying
  /// subscription so the isolate can exit cleanly.
  static Future<void> uninstall() async {
    final inst = _instance;
    _instance = null;
    if (inst != null) {
      await inst._cancel();
    }
  }

  /// Whether this bridge is currently active.
  bool get isActive => _subscription != null;

  Future<void> _cancel() async {
    final s = _subscription;
    _subscription = null;
    if (s != null) {
      await s.cancel();
    }
  }

  void _onRecord(dart_logging.LogRecord rec) {
    final severity = _levelToSeverity(rec.level.value);
    if (severity.severityNumber < _minimumSeverity.severityNumber) {
      return;
    }

    final loggerName =
        rec.loggerName.isNotEmpty ? rec.loggerName : _defaultLoggerName;
    final logger = _provider.getLogger(loggerName);

    final attrMap = <String, Object>{};
    if (rec.error != null) {
      attrMap['exception.type'] = rec.error.runtimeType.toString();
      attrMap['exception.message'] = rec.error.toString();
    }
    if (rec.stackTrace != null) {
      attrMap['exception.stacktrace'] = rec.stackTrace.toString();
    }
    if (rec.zone != null) {
      // Optional: surface the zone hash so multi-isolate or
      // background-zone logs can be correlated.
      attrMap['logging.zone'] = rec.zone.hashCode.toString();
    }

    // `_onRecord` runs in the zone where the bridge was installed — NOT
    // the zone where the user called `log.info(...)`. If we let
    // `logger.emit` resolve `Context.current` from this zone we lose the
    // active span context entirely. `package:logging` already captures
    // the caller's zone on the record; re-enter it so `Context.current`
    // inside `emit` sees the user's span.
    final callerZone = rec.zone ?? Zone.current;
    callerZone.run<void>(() {
      logger.emit(
        timeStamp: rec.time,
        severityNumber: severity,
        severityText: severity.name,
        body: rec.message,
        attributes: attrMap.isEmpty ? null : OTel.attributesFromMap(attrMap),
      );
    });
  }

  /// Translates a `package:logging` `Level.value` to an OTel [Severity].
  ///
  /// Boundaries match the existing `dart:developer` bridge in the SDK
  /// (`DartLogBridge._levelToSeverity`) so consumers see consistent
  /// severities regardless of which bridge produced the record.
  ///
  /// `package:logging` levels of note:
  ///   ALL=0, FINEST=300, FINER=400, FINE=500, CONFIG=700,
  ///   INFO=800, WARNING=900, SEVERE=1000, SHOUT=1200, OFF=2000
  static Severity _levelToSeverity(int level) {
    if (level < 300) return Severity.TRACE;
    if (level < 500) return Severity.TRACE2;
    if (level < 700) return Severity.DEBUG;
    if (level < 800) return Severity.DEBUG2;
    if (level < 900) return Severity.INFO;
    if (level < 1000) return Severity.WARN;
    if (level < 1200) return Severity.ERROR;
    return Severity.FATAL;
  }
}
