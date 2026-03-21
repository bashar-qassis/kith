# Volume Management

All persistent data in the Kith production stack is stored in Docker named volumes.

## Volume Reference

| Volume | Service | Purpose | Backup Priority |
|--------|---------|---------|----------------|
| `postgres_data` | postgres | All application data (users, contacts, notes, etc.) | **Critical** — daily backup required |
| `uploads` | app, worker | User-uploaded files (local disk mode) | **Critical** — contains user documents/photos |
| `caddy_data` | caddy | TLS certificates (Let's Encrypt) | Medium — can be regenerated |
| `caddy_config` | caddy | Caddy configuration state | Low — regenerated from Caddyfile |
| `redis_data` | redis (optional) | Rate limiting state | Low — ephemeral, regenerated on restart |

> **Warning:** MinIO is for development only. Production uses either local disk (`uploads` volume) or real S3. Do not deploy MinIO in production.

## Volume Locations

Docker named volumes are stored at the Docker data root (default: `/var/lib/docker/volumes/`). Each volume appears as a subdirectory named `<project>_<volume>`.

```bash
# List all volumes
docker volume ls

# Inspect a specific volume
docker volume inspect kith_postgres_data
```

## Backup Strategy

### PostgreSQL (Critical)

**Daily automated backup with pg_dump:**
```bash
# Dump database to compressed file
docker compose -f docker-compose.prod.yml exec -T postgres \
  pg_dump -U ${POSTGRES_USER:-kith} ${POSTGRES_DB:-kith_prod} \
  | gzip > backup-$(date +%Y%m%d-%H%M%S).sql.gz
```

**Volume-level backup (alternative):**
```bash
# Stop postgres, backup volume, restart
docker compose -f docker-compose.prod.yml stop postgres
docker run --rm -v kith_postgres_data:/data -v $(pwd)/backups:/backup alpine \
  tar czf /backup/postgres-$(date +%Y%m%d).tar.gz -C /data .
docker compose -f docker-compose.prod.yml start postgres
```

Recommendation: automate daily pg_dump via cron and retain 7 daily + 4 weekly backups.

### Uploads (Critical — local disk mode only)

If using S3 storage (`AWS_S3_BUCKET` is set), this volume is unused and files are in S3.

**rsync to backup location:**
```bash
docker run --rm -v kith_uploads:/data -v /path/to/backup:/backup alpine \
  cp -a /data/. /backup/
```

**S3 sync (if backing up to S3):**
```bash
aws s3 sync /path/to/uploads-backup s3://your-backup-bucket/uploads/
```

### Caddy (Medium)

TLS certificates are stored in `caddy_data`. If lost, Caddy will automatically request new certificates from Let's Encrypt. No routine backup needed, but backup before major migrations to avoid rate limit issues.

## Restore Procedures

### Restore PostgreSQL

```bash
# Stop the app and worker
docker compose -f docker-compose.prod.yml stop app worker

# Restore from pg_dump
gunzip < backup-20240101-120000.sql.gz | \
  docker compose -f docker-compose.prod.yml exec -T postgres \
  psql -U ${POSTGRES_USER:-kith} ${POSTGRES_DB:-kith_prod}

# Restart services
docker compose -f docker-compose.prod.yml up -d
```

### Restore Uploads

```bash
docker run --rm -v kith_uploads:/data -v /path/to/backup:/backup alpine \
  cp -a /backup/. /data/
```

## Disaster Recovery

1. Fresh server: install Docker and Docker Compose
2. Clone the repository
3. Copy `.env` from secure backup
4. `docker build -t kith:latest .`
5. Restore `postgres_data` volume from backup
6. Restore `uploads` volume from backup (if using local storage)
7. `docker compose -f docker-compose.prod.yml up -d`
8. Verify: `curl http://localhost/health/ready`
