# otel_logging

Bridges [`package:logging`](https://pub.dev/packages/logging) records into the
[Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry)
so any Dart application using the de-facto-standard Dart logging package gets
trace/span correlation in its log records automatically.

## Why

`package:logging` is what every Dart server framework and most Flutter apps use
for structured application logs. Without a bridge, every consumer who wants
trace-id correlation in their backend has to write the same ~15 lines of
`Logger.root.onRecord.listen(...)` plumbing — easy to get the level mapping
subtly wrong. This package is that plumbing, written once.

The bridge is **opt-in**: the OTel SDK does not depend on `package:logging`.
Add this package only when you want the integration.

## Usage

```dart
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_logging/otel_logging.dart';
import 'package:logging/logging.dart';

Future<void> main() async {
  await OTel.initialize(serviceName: 'my-app');

  // After OTel.initialize so the default LoggerProvider exists.
  PackageLoggingBridge.install();

  Logger.root.level = Level.ALL;

  Logger('weather.api').info('serving forecast');

  // Records emitted from inside an active span are auto-correlated.
  await OTel.tracer().startActiveSpan('serve', (_) async {
    Logger('handler').warning('upstream slow');
  });

  // Cancel the StreamSubscription before the program exits, otherwise
  // the open subscription keeps the Dart isolate alive after main returns.
  await PackageLoggingBridge.uninstall();
  await OTel.shutdown();
}
```

### Severity mapping

`package:logging` `Level.value` is mapped to OTel `Severity` using the same
boundaries as the SDK's existing `dart:developer` bridge:

| `package:logging`      | `Level.value` | OTel `Severity` |
| ---------------------- | ------------- | --------------- |
| `ALL` (anything < 300) | 0+            | `TRACE`         |
| `FINEST`               | 300           | `TRACE2`        |
| `FINER`                | 400           | `TRACE2`        |
| `FINE`                 | 500           | `DEBUG`         |
| `CONFIG`               | 700           | `DEBUG2`        |
| `INFO`                 | 800           | `INFO`          |
| `WARNING`              | 900           | `WARN`          |
| `SEVERE`               | 1000          | `ERROR`         |
| `SHOUT`                | 1200          | `FATAL`         |

### Attributes

- `exception.type` — set when the record has an `error` (uses
  `runtimeType.toString()`).
- `exception.message` — set when the record has an `error` (uses
  `error.toString()`).
- `exception.stacktrace` — set when the record has a `stackTrace`.
- `logging.zone` — `hashCode` of the originating `Zone`. Useful when
  correlating logs across isolates/zones; ignore otherwise.

The OTel logger name (instrumentation scope) defaults to the
`Logger`'s `name`, falling back to `package.logging` for `Logger.root`
records.

### Existing `Logger.root.onRecord` subscribers keep firing

Installing the bridge is **additive**. If your app already prints log
records to stdout via a `Logger.root.onRecord.listen(...)` subscriber,
those continue to fire. That matters for Cloud Run / Cloud Functions
where the platform also collects stdout.

## Lifecycle

The bridge holds a `StreamSubscription` on `Logger.root.onRecord`. Like
any open subscription, **an open subscription keeps the Dart isolate
alive past `main()`**. Always:

```dart
await PackageLoggingBridge.uninstall();
await OTel.shutdown();
```

before letting `main()` return. Forgetting to uninstall is the same
class of bug as
[issue #33 in the SDK](https://github.com/MindfulSoftwareLLC/dartastic_opentelemetry/issues/33)
(short-lived CLIs hanging because a Timer/subscription was never
cancelled).

## License

Apache 2.0 — see `LICENSE`.
