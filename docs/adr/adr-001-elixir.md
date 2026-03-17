# ADR-001: Elixir over Rails/Django

**Status:** Accepted
**Date:** 2026-03-17

## Context

Kith is a self-hosted Personal Relationship Manager requiring reliable background job processing, real-time UI updates, and multi-tenant concurrency. We needed to choose a backend language and framework that would serve these needs without introducing unnecessary infrastructure complexity.

## Decision

Use Elixir with the Phoenix framework as the backend.

## Consequences

### Positive

- **OTP fault isolation:** Supervisors provide process-level fault isolation for background jobs and WebSocket connections. A crashing job worker does not bring down the web process.
- **Native Oban integration:** Oban is PostgreSQL-backed, meaning no external message broker (Redis, RabbitMQ) is required. Job insertion is transactional via Ecto.Multi.
- **LiveView eliminates JS framework complexity:** Server-rendered reactive UI via Phoenix LiveView removes the need for a separate React/Vue frontend, reducing the number of moving parts and build pipelines.
- **Pattern matching and immutability:** Elixir's functional model and pattern matching make domain logic explicit and easier to reason about, especially for complex relationship/reminder workflows.
- **Concurrency model:** The BEAM VM handles large numbers of concurrent connections efficiently — well-suited for multi-tenant self-hosted workloads with per-user reminder timers and Immich sync jobs.

### Negative

- **Smaller hiring pool:** Elixir engineers are fewer in number than Ruby or Python engineers, which may slow future team growth.
- **Ecosystem maturity:** Some libraries (e.g., file uploads, certain OAuth flows) require more integration work than Rails equivalents.

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Ruby on Rails | Strong ecosystem but Global Interpreter Lock limits concurrency; ActionCable more complex than LiveView for real-time; no native BEAM fault isolation |
| Django | Python ecosystem is large, but async support is bolted on; Celery requires Redis/RabbitMQ broker for background jobs |
| Node.js/Express | Async-native but callback/promise complexity at scale; no OTP supervision tree; job queues require external brokers |
