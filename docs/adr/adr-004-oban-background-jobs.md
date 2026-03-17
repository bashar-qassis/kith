# ADR-004: Oban for Background Jobs

**Status:** Accepted
**Date:** 2026-03-17

## Context

Kith requires reliable background job processing for: contact reminders, transactional email delivery, Immich photo sync, and data export. Jobs must survive application restarts, support retry/backoff on failure, and be insertable within database transactions to avoid phantom jobs on rollback.

## Decision

Use Oban (PostgreSQL-backed) as the background job processor.

Cross-reference: See `docs/oban-transactionality.md` for `Ecto.Multi` integration patterns used when inserting jobs transactionally alongside domain writes.

## Consequences

### Positive

- **No additional infrastructure:** Oban uses the existing PostgreSQL database as its job queue. No Redis, RabbitMQ, or other broker required in the Docker stack.
- **Transactional job insertion:** Jobs inserted via `Oban.insert/2` inside an `Ecto.Multi` are only committed if the surrounding transaction succeeds. This eliminates the ghost-job problem (job enqueued but domain write rolled back).
- **Built-in retry and backoff:** Configurable per-worker retry limits and exponential backoff are provided out of the box. Failed jobs are retained in the `oban_jobs` table for inspection.
- **Cron scheduling:** `Oban.Plugins.Cron` handles scheduled jobs (e.g., `ContactPurgeWorker` for 30-day trash cleanup, daily reminder digests) without an external cron daemon.
- **Multi-node via LISTEN/NOTIFY:** Multiple app nodes coordinate via PostgreSQL's `LISTEN/NOTIFY`, enabling horizontal scaling without a separate coordination layer.
- **Oban Web dashboard:** The `oban_web` package provides a LiveView-based job monitoring dashboard, available in the admin UI.

### Negative

- **PostgreSQL load:** Job polling and queue maintenance add read/write load to the primary PostgreSQL instance. At very high job volumes, this may require queue tuning or a read replica.
- **Not suitable for very high throughput:** For millions of jobs per minute, a dedicated broker (Kafka, RabbitMQ) would outperform PostgreSQL-backed queuing. Kith's expected job volumes are modest.

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Exq (Redis-based) | Requires Redis as an additional infrastructure dependency; job insertion is not transactional with PostgreSQL writes |
| Broadway | Designed for high-throughput data pipelines (Kafka, SQS consumers), not general-purpose job queuing with retry semantics |
| Custom GenServer | No persistence across restarts; no retry logic; reinvents scheduling; high maintenance burden |
