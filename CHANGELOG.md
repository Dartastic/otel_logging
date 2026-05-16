# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.1-wip]

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
  emitted inside `startActiveSpanAsync` reached Loki without a
  `trace_id` / `span_id`, breaking the Grafana log→trace pivot.
  Pinned down by `test/integration/lgtm_loki_test.dart`.
