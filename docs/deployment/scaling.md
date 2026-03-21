# Scaling Notes

> **v1 scope:** Kith v1 is a single-node deployment. This document describes how to scale beyond a single node when needed. None of these changes are required for v1.

## Architecture Overview

Kith is designed for stateless horizontal scaling:
- **Application state:** PostgreSQL (single source of truth)
- **File storage:** S3 (shared) or local disk (single-node only)
- **Background jobs:** Oban (PostgreSQL-backed, multi-node safe)
- **Rate limiting:** ETS (single-node) or Redis (shared)

## 1. Stateless App Containers

Phoenix app containers hold no local state. All persistent data lives in PostgreSQL, file storage (S3), and optionally Redis. This means you can run multiple `app` replicas behind a load balancer.

**What to do:**
- Scale replicas: `docker compose -f docker-compose.prod.yml up -d --scale app=3`
- Add a load balancer in front of app replicas
- Switch to S3 storage (local disk doesn't work across nodes)

## 2. Load Balancer Configuration

When running multiple `app` replicas, a load balancer distributes HTTP traffic.

**Requirements:**
- **Sticky sessions** for LiveView WebSocket connections — route by cookie or IP hash. Without this, LiveView reconnections may hit a different node and lose state.
- **WebSocket upgrade support** — the LB must pass `Upgrade: websocket` headers through to the backend
- **Health check** against `/health/ready` — only route traffic to healthy instances

**Options:** Caddy (already included), nginx, HAProxy, cloud load balancers (AWS ALB, GCP LB).

> **Important:** Sticky sessions are the #1 gotcha when scaling Phoenix horizontally. LiveView maintains a WebSocket connection to a specific server process. If the connection drops and reconnects to a different node, the LiveView state is lost and the user sees a reconnection flash.

## 3. Oban Multi-Node

Oban processes jobs across multiple nodes using PostgreSQL advisory locks and LISTEN/NOTIFY. No configuration change is needed — just run multiple `worker` containers.

**How it works:**
- Each worker polls the `oban_jobs` table
- PostgreSQL advisory locks ensure each job is processed by exactly one worker
- LISTEN/NOTIFY provides near-instant job pickup

**What to do:**
- Scale workers: `docker compose -f docker-compose.prod.yml up -d --scale worker=2`
- No code changes required

## 4. Redis for Rate Limiting

When `RATE_LIMIT_BACKEND=redis`, all app replicas share rate limit counters via Redis.

**Why this matters:** With ETS (default), each node tracks rates independently. An attacker sending requests to N nodes effectively gets N times the rate limit budget. Redis provides a single shared counter.

**What to do:**
1. Uncomment the `redis` service in `docker-compose.prod.yml`
2. Set `RATE_LIMIT_BACKEND=redis` in `.env`
3. Set `REDIS_URL=redis://redis:6379` in `.env`

## 5. Phoenix PubSub Clustering

For LiveView updates to propagate across nodes (e.g., user A updates a contact on node 1, user B sees the update on node 2), Phoenix PubSub needs a distributed adapter.

**Options:**
- `Phoenix.PubSub.Redis` — simplest, uses Redis pub/sub
- `libcluster` + Erlang distribution — no external dependencies, but requires EPMD port management and cluster discovery

**v2 concern:** This is only needed if you require real-time cross-node updates. For v1 single-node, the default PubSub (local) works fine.

## 6. Database Connection Pooling

With N app replicas, total database connections = N × `POOL_SIZE`. PostgreSQL's default `max_connections` is 100.

**What to watch:**
- 3 app replicas × 10 pool size = 30 connections (fine)
- 10 app replicas × 10 pool size = 100 connections (at limit)

**What to do if you hit the limit:**
- Use PgBouncer as a connection pooler between app and PostgreSQL
- Reduce `POOL_SIZE` per replica
- Increase PostgreSQL `max_connections` (requires more memory)

## Summary

| Concern | Single-Node (v1) | Multi-Node (v2) |
|---------|------------------|-----------------|
| App replicas | 1 | N (behind LB with sticky sessions) |
| Worker replicas | 1 | N (Oban handles coordination) |
| File storage | Local disk | S3 |
| Rate limiting | ETS | Redis |
| PubSub | Local | Redis or Erlang distribution |
| DB connections | POOL_SIZE | N × POOL_SIZE (consider PgBouncer) |
