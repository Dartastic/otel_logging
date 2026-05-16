// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Integration test: install the bridge, emit a `package:logging`
/// record, flush, then poll Loki's HTTP API to verify the record
/// arrived and the OTel-side attributes survived the round trip.
///
/// Skipped when no LGTM stack is reachable. Bring one up first:
///   docker compose -f tool/lgtm/docker-compose.yml up -d
///
/// Env vars:
///   LGTM_OTLP_ENDPOINT — OTLP gRPC endpoint (default http://localhost:4317)
///   LGTM_LOKI_URL     — Loki HTTP API base (default http://localhost:3100)
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
const _defaultLoki = 'http://localhost:3100';

void main() {
  group('LGTM end-to-end', () {
    final otlpEndpoint =
        Platform.environment['LGTM_OTLP_ENDPOINT'] ?? _defaultOtlp;
    final lokiUrl = Platform.environment['LGTM_LOKI_URL'] ?? _defaultLoki;

    test('bridged log record appears in Loki', () async {
      final lokiOk = await _lokiReachable(lokiUrl);
      final otlpOk = await _portOpen(otlpEndpoint);
      if (!lokiOk || !otlpOk) {
        markTestSkipped(
          'LGTM not reachable (loki=$lokiOk otlp=$otlpOk) — start it with '
          '`docker compose -f tool/lgtm/docker-compose.yml up -d` and rerun.',
        );
        return;
      }

      // Service name carries a per-run suffix so the Loki query only
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
      // that the trace_id flows through to Loki. The bridge's zone
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

      final record = await _pollLokiForServiceMarker(
        lokiUrl: lokiUrl,
        serviceName: serviceName,
        marker: marker,
        timeout: const Duration(seconds: 30),
      );
      expect(
        record,
        isNotNull,
        reason: 'Loki never returned a record matching service=$serviceName '
            'body~="$marker". Check the LGTM container logs.',
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

/// Loki readiness probe.
Future<bool> _lokiReachable(String lokiUrl) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    final req = await client.getUrl(Uri.parse('$lokiUrl/ready'));
    final resp = await req.close().timeout(const Duration(seconds: 2));
    await resp.drain<void>();
    client.close();
    return resp.statusCode == 200;
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

/// Poll Loki's `query_range` API for the marker string scoped to the
/// emitting service. Returns the first matching stream's label map
/// (which Loki uses for both stream labels and promoted structured
/// metadata like `trace_id` / `span_id`), or `null` on timeout.
Future<Map<String, String>?> _pollLokiForServiceMarker({
  required String lokiUrl,
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
        // LogQL: select streams labelled by service_name and grep for marker.
        final query = '{service_name="$serviceName"} |= `$marker`';
        final uri = Uri.parse('$lokiUrl/loki/api/v1/query_range').replace(
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
