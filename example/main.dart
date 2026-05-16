// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Minimal example: install the bridge, emit a few records (one of them
/// inside an active span so trace_id/span_id correlation lights up), then
/// uninstall and shut down cleanly.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:logging/logging.dart';
import 'package:otel_logging/otel_logging.dart';

Future<void> main() async {
  await OTel.initialize(
    serviceName: 'logging-bridge-example',
    serviceVersion: '0.0.1',
  );

  PackageLoggingBridge.install();

  Logger.root.level = Level.ALL;

  // Off-span — no trace correlation.
  Logger('startup').info('process started');

  // In-span — record will carry the active span's trace_id / span_id.
  await OTel.tracer().startActiveSpanAsync<void>(
    name: 'serve-request',
    fn: (_) async {
      Logger('handler').warning('upstream took >500ms');
    },
  );

  // Lifecycle: cancel the subscription before main() returns.
  await PackageLoggingBridge.uninstall();
  await OTel.shutdown();
}
