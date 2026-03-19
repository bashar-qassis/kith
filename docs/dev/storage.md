# Local Storage with MinIO (Dev)

## MinIO Setup

MinIO is included in `docker-compose.dev.yml` as an S3-compatible object store for development.

- **MinIO Console:** http://localhost:9001
- **S3 API Endpoint:** http://localhost:9000
- **Default Credentials:** `MINIO_ROOT_USER=minioadmin`, `MINIO_ROOT_PASSWORD=minioadmin`

## Creating the Dev Bucket

1. Open MinIO Console at http://localhost:9001
2. Log in with `minioadmin` / `minioadmin`
3. Go to **Buckets** → **Create Bucket**
4. Name: `kith-dev`
5. Click **Create**

## Using S3 Backend in Dev

Add to your `.env`:

```env
AWS_S3_BUCKET=kith-dev
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_REGION=us-east-1
AWS_S3_ENDPOINT=http://localhost:9000
```

## Default: Local Storage

Without S3 config, files are stored on local disk under `priv/uploads/`.
Files are served by the authenticated `UploadsController` at `/uploads/*`.
