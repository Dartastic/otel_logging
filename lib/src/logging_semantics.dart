// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// Bridge-specific attribute keys that have no upstream registry
/// equivalent.
///
/// The OTel registry's `log.*` namespace covers log files and
/// streams, not in-process logger routing, so the zone key lives
/// under a package-local `logging.*` namespace. If the registry
/// grows a convention for this, these can `@Deprecated`-pivot.
enum LoggingSemantics implements OTelSemantic {
  /// `hashCode` of the `Zone` the record was emitted from. Useful
  /// when correlating logs across isolates/zones; ignore otherwise.
  zone('logging.zone');

  const LoggingSemantics(this.key);

  @override
  final String key;

  @override
  String toString() => key;
}
