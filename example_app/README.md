# otel_logging example app

A standalone runnable demo of `otel_logging`
exporting telemetry to a local OTLP-capable backend (any open-source
all-in-one dev-observability container works).

## Run

```sh
# 1. Start any OTLP-compatible backend that also exposes a logs UI or
#    query API, listening on 4317 (gRPC) and 4318 (HTTP).

# 2. Run the app
cd example_app
dart pub get
dart run bin/main.dart
```

## What it does

Emits `package:logging` records at every level + one record with an
attached exception + stack trace. Some records are emitted outside an
active span (no trace correlation), others inside (full trace
correlation).

| Record | `package:logging` level | OTel `Severity` | Inside a span? |
|---|---|---|---|
| `finest — TRACE2` | `FINEST` | `TRACE2` | no |
| `finer — TRACE2` | `FINER` | `TRACE2` | no |
| `fine — DEBUG` | `FINE` | `DEBUG` | no |
| `config — DEBUG2` | `CONFIG` | `DEBUG2` | no |
| `process started` | `INFO` | `INFO` | no |
| `received request` | `INFO` | `INFO` | yes |
| `upstream took >500ms` | `WARNING` | `WARN` | yes |
| `db call failed` (with `StateError` + stack) | `SEVERE` | `ERROR` | yes |
| `responding 200` | `INFO` | `INFO` | yes |
| `process exiting` | `SHOUT` | `FATAL` | no |

## Where to look

In your logs backend, search for:

- Query: `{service_name="logging-bridge-example-app"}`
- Records with a `trace_id` field pivot to the corresponding trace in
  any backend that correlates logs to traces.
- The `db call failed` record carries `exception.type`,
  `exception.message`, and `exception.stacktrace` attributes.

## Env

| Variable | Default | Purpose |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTLP HTTP endpoint (the SDK's default protocol). For gRPC, also set `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` and point at port 4317. |
