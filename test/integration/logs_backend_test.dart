// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Integration test: install the bridge, emit a `package:logging`
/// record, flush, then poll the logs backend's query API to verify the
/// record arrived and the OTel-side attributes survived the round trip.
///
/// Skipped when no logs backend is reachable. Bring one up first: any
/// OTLP-compatible backend on 4317/4318 that also exposes a log
/// range-query API.
///
/// Env vars:
///   OTLP_ENDPOINT — OTLP endpoint (default http://localhost:4318,
///                   OTLP/HTTP — the SDK's default protocol)
///   LOG_QUERY_URL — full log range-query URL for your backend. There is
///                   no vendor-neutral default, so unset ⇒ this test
///                   skips. The backend must accept a `query` parameter
///                   in log-selector form (see `_pollLogsForServiceMarker`)
///                   plus `start` / `end` nanosecond timestamps.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:logging/logging.dart' as dart_logging;
import 'package:otel_logging/otel_logging.dart';
import 'package:test/test.dart';

// OTLP/HTTP default port — the SDK's default protocol is `http/protobuf`.
const _defaultOtlp = 'http://localhost:4318';
const _defaultOtlpPort = 4318;

void main() {
  group('OTLP backend end-to-end', () {
    final otlpEndpoint = Platform.environment['OTLP_ENDPOINT'] ?? _defaultOtlp;
    // No default: the range-query path differs per backend, so the caller
    // supplies the whole URL or the test skips.
    final logApiUrl = Platform.environment['LOG_QUERY_URL'];

    test('bridged log record appears in the logs backend', () async {
      final logApiOk = await _logApiReachable(logApiUrl);
      final otlpOk = await _portOpen(otlpEndpoint);
      if (logApiUrl == null || !logApiOk || !otlpOk) {
        markTestSkipped(
          'Logs backend not reachable (logs=$logApiOk otlp=$otlpOk) — start '
          'any OTLP-compatible backend with a log range-query API, set '
          'LOG_QUERY_URL to that query endpoint, and rerun.',
        );
        return;
      }

      // Service name carries a per-run suffix so the log query only
      // matches this run; otherwise repeated runs accrete and the
      // assertion below would match a stale record.
      final runId = DateTime.now().millisecondsSinceEpoch.toString();
      final serviceName = 'logging-bridge-itest-$runId';
      const marker = 'integration-test-needle';

      await OTel.reset();
      await OTel.initialize(
        serviceName: serviceName,
        serviceVersion: '0.0.1',
        endpoint: otlpEndpoint,
      );
      PackageLoggingBridge.install();
      dart_logging.Logger.root.level = dart_logging.Level.ALL;

      // Emit one record inside an active span so we can also assert
      // that the trace_id flows through to the logs backend. The bridge's zone
      // bug (listener fires in the install zone, not the caller's
      // zone) regressed silently before — pin it down here.
      late String expectedTraceIdHex;
      late String expectedSpanIdHex;
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'itest-span',
        fn: (span) async {
          expectedTraceIdHex = span.spanContext.traceId.hexString;
          expectedSpanIdHex = span.spanContext.spanId.hexString;
          dart_logging.Logger('itest').info(marker);
        },
      );

      await PackageLoggingBridge.uninstall();
      await OTel.loggerProvider().forceFlush();
      await OTel.shutdown();

      final record = await _pollLogsForServiceMarker(
        logApiUrl: logApiUrl,
        serviceName: serviceName,
        marker: marker,
        timeout: const Duration(seconds: 30),
      );
      expect(
        record,
        isNotNull,
        reason: 'Logs backend never returned a record matching '
            'service=$serviceName body~="$marker". Check your backend\'s '
            'own logs.',
      );
      expect(
        record!['trace_id'],
        expectedTraceIdHex,
        reason: 'Bridge dropped trace context — record had no trace_id. '
            'This usually means the bridge listener is reading '
            'Context.current from the wrong zone.',
      );
      expect(record['span_id'], expectedSpanIdHex);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}

/// Logs backend readiness probe: TCP-connect to the host/port of the
/// configured query URL. Deliberately not an HTTP readiness path —
/// backends disagree on where (and whether) they expose one, and the
/// query URL itself is the only address this test is told about.
/// A null URL means the env var is unset, i.e. not configured.
Future<bool> _logApiReachable(String? logApiUrl) async {
  if (logApiUrl == null) return false;
  final uri = Uri.tryParse(logApiUrl);
  if (uri == null || uri.host.isEmpty) return false;
  try {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final socket = await Socket.connect(uri.host, port,
        timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on Exception {
    return false;
  }
}

/// TCP probe on the OTLP endpoint — confirms the export port is open.
Future<bool> _portOpen(String endpoint) async {
  try {
    final uri = Uri.parse(endpoint);
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? uri.port : _defaultOtlpPort;
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on Exception {
    return false;
  }
}

/// Poll the backend's range-query API for the marker string scoped to
/// the emitting service. Returns the first matching stream's label map
/// (backends commonly carry both stream labels and promoted structured
/// metadata like `trace_id` / `span_id` there), or `null` on timeout.
Future<Map<String, String>?> _pollLogsForServiceMarker({
  required String logApiUrl,
  required String serviceName,
  required String marker,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  final client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final start = (DateTime.now()
                    .subtract(const Duration(minutes: 5))
                    .millisecondsSinceEpoch *
                1000000)
            .toString();
        final end =
            (DateTime.now().millisecondsSinceEpoch * 1000000).toString();
        // Log-selector syntax: select streams labelled by service_name
        // and filter for the marker. The configured backend must accept
        // this form; the whole query URL comes from LOG_QUERY_URL so no
        // vendor-specific path is hardcoded here.
        final query = '{service_name="$serviceName"} |= `$marker`';
        final uri = Uri.parse(logApiUrl).replace(
          queryParameters: {'query': query, 'start': start, 'end': end},
        );
        final req = await client.getUrl(uri);
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final parsed = jsonDecode(body) as Map<String, dynamic>;
          final result =
              (parsed['data'] as Map<String, dynamic>?)?['result'] as List?;
          if (result != null && result.isNotEmpty) {
            final first = result.first as Map<String, dynamic>;
            final stream = first['stream'] as Map<String, dynamic>?;
            if (stream != null) {
              return stream.map((k, v) => MapEntry(k, v.toString()));
            }
          }
        } else {
          await resp.drain<void>();
        }
      } on Exception {
        // Transient — keep polling.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close();
  }
  return null;
}
