<!-- dartastic-header:start -->
# OpenTelemetry instrumentation for `logging`

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenTelemetry Specification](https://img.shields.io/badge/OpenTelemetry-Specification-blueviolet)](https://opentelemetry.io/docs/specs/otel/)

`otel_logging` is an [OpenTelemetry](https://opentelemetry.io/) instrumentation for `logging` that
easily adds standard observability to applications that use `logging`.  This package depends on 
[dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package can be used with any OTel backend because it's compliant with the OpenTelemetry Specification.

This package supports Android, iOS, Linux, macOS, Web and Windows, for versions of `logging` that support those platforms. It is WASM-ready.

This Apache-2.0 package is professionally maintained and supported with 💙 by Michael Bushe,
Dart and Flutter Maintainer at OpenTelemetry and the creator of [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
and [dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api). This package is professionally supported by
[Dartastic.io](https://dartastic.io).

---
## Dartastic.io: AI Code Healing and Real User Monitoring for Flutter

**See what your users experience. Find problems with Flutter apps in production. Fix them with AI.**

[Dartastic.io](https://dartastic.io) brings AI code healing, real user monitoring, and OpenTelemetry observability together in one platform built for Dart and Flutter. (Patents pending)

![Dartastic AI answering "Why did crashes jump after the last release?" over a Flutter App Health dashboard](https://dartastic.io/img/pub-dev/HomePageCrashesQuestion.png)

### Dartastic AI — From Production Problems to Code Fixes

Dartastic AI analyzes production telemetry alongside your application source code to diagnose problems and propose fixes.

- **Investigate production issues** using crashes, errors, traces, metrics, and real user telemetry.
- **Find the offending code** by connecting observed problems with your application's source in Dartastic Pub or your source code repos.
- **Generate code patches** that address the underlying problems.
- **Create actionable issues** in your issue tracker, complete with findings and the proposed code patch.

### Dartastic RUM — See What Your Users See

Understand how people actually experience your Flutter application.

- **Replay user sessions** in the Dartastic Observatory session player.
- **Choose your replay fidelity**, from privacy-preserving widget outlines to pixel-level reproductions of the user experience.
- **Investigate real user problems** using session replay and production observability data.

![Dartastic RUM Session Replay](https://dartastic.io/img/pub-dev/session-replay.png)

### Dartastic Observatory — Observability Built for Flutter

A complete observability backend where Flutter and Dart are first-class citizens.

- **Flutter-specific dashboards** for application performance, health, and reliability.
- **Alerts and notifications** through email, Slack, and PagerDuty.
- **Dartastic Cloud Observatory** — Start with a 30-day free trial on isolated, shared infrastructure, as low as $39/mo.
- **Dartastic Hosted Observatory** — Run the observability stack in a private managed environment, sized from Mini to Enterprise XL.
- **Dartastic Self-Hosted Observatory** — The whole platform inside your own network. Your keys, your cluster, with nothing leaving your perimeter.

### Dartastic Native OTel Runtime — Native OpenTelemetry Performance

Collect production telemetry without burdening Flutter's main isolate.

- **Native OpenTelemetry runtime** that moves telemetry processing off the main isolate.
- **Native crash reporting** for problems that Dart can't catch.
- **Widget performance diagnostics** to identify janky widgets.
- **On-device PII filtering** before sensitive data leaves your application.
- **Source-level error diagnostics** powered by the Dartastic Symbolizer API.
- **Platform-native metrics** for iOS, Android, and Linux, including iOS MetricKit and Android Vitals.
- **OpenTelemetry compatibility** — Send telemetry to Dartastic Observatory or any OpenTelemetry platform.

### Dartastic Labs — OpenTelemetry Integrations

Instrument more of your application without writing everything yourself.

- **650+ open-source integrations** for Dart and Flutter libraries and services, including Dio, Shelf, Logger, Anthropic, AWS, Azure, and Stripe. Look for otel_* on pub.dev.

### More Dartastic Tools

**[Dartastic Pub](https://dartastic.io/pub)**

A private Dart package registry for sharing packages and plugins with your team, partners, and customers.

**[Dartastic Symbolizer](https://dartastic.io/symbolizer)**

Turn production errors into lines of source code through a web API, while keeping your source code artifacts private.

### Professional Support and Training

Dartastic.io offers commercial support for the open-source `dartastic_opentelemetry` and `dartastic_opentelemetry_api` packages and the complete Dartastic product suite.

- **Professional support** with available around-the-clock coverage and response times under four hours on qualifying plans.
- **OpenTelemetry training** for teams instrumenting Dart, Flutter, mobile, and web applications.

### Open Standards. No Mandatory Backend.

The Dartastic OpenTelemetry API and SDK are open source and standards-based. You can use them independently of Dartastic's commercial services and send telemetry to any compatible OpenTelemetry backend.

Dartastic's commercial products add native performance, advanced diagnostics, session replay, AI-assisted remediation, and managed observability services.

**[Explore Dartastic.io](https://dartastic.io)**

---
<!-- dartastic-header:end -->

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
