# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0-wip]

## [0.2.0] - 2026-08-10

### Changed

- Semantic conventions updated to the current OTel registry: deprecated
  attribute keys are no longer emitted (`db.system` -> `db.system.name`,
  `db.operation` -> `db.operation.name`, `rpc.system` -> `rpc.system.name`,
  with `rpc.service` folded into a fully-qualified `rpc.method`).
- Dependency floors raised to `dartastic_opentelemetry ^1.1.0-beta.12` and
  `dartastic_opentelemetry_api ^1.0.0-rc.1`. The previous floors declared
  compatibility with API versions that predate the semconv enums this
  package uses and could not actually resolve-and-compile.
- `repository` URL corrected to the canonical `Dartastic` org casing so
  pub.dev repository verification succeeds.
- Attribute keys are now emitted via semconv enum constants
  (`ExceptionAttributes` from the API, plus a package-local
  `LoggingSemantics` enum for the non-registry `logging.zone` key)
  instead of raw string literals. Wire format is unchanged.
- The runnable `example_app/` now depends only on the OSS SDK and a
  self-contained `docker run` backend, so it works out of the box for
  every consumer.

### Added

- `PackageLoggingBridge.install()` / `uninstall()` — subscribes to
  `package:logging`'s `Logger.root.onRecord` and emits OTel log records
  via the active `LoggerProvider`. Each `Logger(name)` becomes its own
  OTel instrumentation scope; severity is mapped to OTel `Severity`
  using the same boundaries as the SDK's existing `dart:developer`
  bridge.
- `error` / `stackTrace` on a record become `exception.type` /
  `exception.message` / `exception.stacktrace` attributes.
- Bridge holds a single `StreamSubscription` and cancels it on
  `uninstall()`, so the isolate exits cleanly after `main()` (related
  to issue #33 in the SDK repo).
- Trace-log correlation: the bridge re-enters the caller's `Zone`
  (captured by `package:logging` on `LogRecord.zone`) before calling
  `Logger.emit`, so `Context.current` resolves to the user's active
  span instead of the install-zone's context. Without this, records
  emitted inside `startActiveSpanAsync` reached the logs backend
  without a `trace_id` / `span_id`, breaking log-to-trace correlation.
  Pinned down by `test/integration/logs_backend_test.dart`.
