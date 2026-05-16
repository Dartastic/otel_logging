// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Runnable demo of `otel_logging` against a local
/// LGTM stack.
///
/// Run the stack:
///   docker compose -f ../../../tool/lgtm/docker-compose.yml up -d
///
/// Then run this app:
///   dart run bin/main.dart
///
/// Open Grafana (http://localhost:3000), pick the Loki datasource in
/// Explore, query `{service_name="logging-bridge-example-app"}`. Each
/// emitted record carries the level → OTel severity mapping; records
/// emitted inside an active span also carry the trace_id / span_id of
/// that span so you can pivot from Loki to Tempo with one click.
library;

import 'dart:async';
import 'dart:io';

// Example apps use the Pro SDK to demonstrate the one-character
// switch (OTel.initialize -> DOTel.initialize). The package source
// still imports the OSS SDK directly so non-Pro users can use it.
import 'package:dartastic_opentelemetry_pro/dartastic_opentelemetry_pro.dart';
import 'package:logging/logging.dart';
import 'package:otel_logging/otel_logging.dart';

const _serviceName = 'logging-bridge-example-app';
// 4318 = OTLP/HTTP default port (the SDK's default protocol is
// `http/protobuf`). Use 4317 only with `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`.
const _defaultEndpoint = 'http://localhost:4318';

Future<void> main(List<String> args) async {
  final endpoint =
      Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ?? _defaultEndpoint;

  print('==> exporting to $endpoint as $_serviceName');

  await DOTel.initialize(
    serviceName: _serviceName,
    serviceVersion: '0.0.1',
    endpoint: endpoint,
  );

  PackageLoggingBridge.install();
  Logger.root.level = Level.ALL;

  // Off-span — these log records carry no trace context, so in Loki
  // they appear as standalone entries with no Tempo pivot.
  Logger('startup').finest('finest — TRACE2');
  Logger('startup').finer('finer — TRACE2');
  Logger('startup').fine('fine — DEBUG');
  Logger('startup').config('config — DEBUG2');
  Logger('startup').info('process started');

  // In-span — every record inside this active span inherits trace_id
  // / span_id from Context.current, so Loki entries pivot straight to
  // the Tempo trace via Grafana's datasource correlation.
  await DOTel.tracer().startActiveSpanAsync<void>(
    name: 'handle-request',
    fn: (_) async {
      Logger('handler').info('received request');
      Logger('handler').warning('upstream took >500ms');

      try {
        await _simulatedDbCall();
      } catch (e, st) {
        // The bridge surfaces error + stackTrace as
        // exception.type / exception.message / exception.stacktrace
        // attributes on the log record.
        Logger('handler').severe('db call failed', e, st);
      }

      Logger('handler').info('responding 200');
    },
  );

  // SHOUT — maps to OTel FATAL. Off-span again so this is a top-level
  // alert record.
  Logger('shutdown').shout('process exiting');

  print('==> flushing + shutting down');
  await PackageLoggingBridge.uninstall();
  await DOTel.shutdown();
  print('==> done. open Grafana at http://localhost:3000 → Explore → '
      'Loki, {service_name="$_serviceName"}');
}

/// Throws on purpose so the example surfaces the
/// error + stack-trace attribute path.
Future<void> _simulatedDbCall() async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  throw StateError('connection pool exhausted');
}
