Create, optimize, or debug Dockerfiles and docker-compose configurations.

## Workflow
1. **Check existing config**: look for `Dockerfile`, `docker-compose.yml`, `.dockerignore`.
2. **Match the project stack**: choose the right base image and build strategy.
3. **Optimize for layer caching and image size**.
4. **Test the build**: `docker build` and `docker compose up` to verify.

## Dockerfile best practices

### Multi-stage builds
Separate build dependencies from runtime:
```dockerfile
# Build stage
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage
FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

### Layer caching
- Copy dependency files first, install, then copy source code.
- Dependencies change less often than source — cache the install layer.
- Order instructions from least to most frequently changing.

### Image size
- Use `-alpine` or `-slim` base images.
- Use multi-stage builds to exclude build tools from runtime image.
- Combine `RUN` commands to reduce layers: `RUN apt-get update && apt-get install -y X && rm -rf /var/lib/apt/lists/*`.
- Use `.dockerignore` to exclude `node_modules`, `.git`, tests, docs, etc.

### Security
- Don't run as root: `USER node` or `USER nobody`.
- Don't store secrets in the image — use build secrets or runtime env vars.
- Pin base image versions: `node:20.11-alpine`, not `node:latest`.
- Scan images: `docker scout quickview` or `trivy image`.
- Use `COPY` not `ADD` (unless extracting tarballs).

### Health checks
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
```

## docker-compose best practices

### Service organization
```yaml
services:
  app:
    build: .
    ports: ["3000:3000"]
    depends_on:
      db:
        condition: service_healthy
    env_file: .env

  db:
    image: postgres:16-alpine
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      retries: 5

volumes:
  db_data:
```

### Key patterns
- **Named volumes** for persistent data (databases, uploads).
- **`depends_on` with health checks** for proper startup order.
- **`env_file`** for environment variables (never commit `.env`).
- **`profiles`** for optional services (monitoring, debug tools).
- **Networks**: use custom networks for service isolation when multiple stacks coexist.

## Common base images by stack
| Stack | Build | Runtime |
|---|---|---|
| Node.js | `node:20-alpine` | `node:20-alpine` |
| Python | `python:3.12-slim` | `python:3.12-slim` |
| Go | `golang:1.22-alpine` | `alpine:3.19` or `scratch` |
| Rust | `rust:1.77-alpine` | `alpine:3.19` or `scratch` |
| Java | `eclipse-temurin:21-jdk-alpine` | `eclipse-temurin:21-jre-alpine` |

## .dockerignore
Always create one. Minimum:
```
.git
node_modules
.env
*.md
tests/
docs/
.github/
```

## Debugging
- `docker logs <container>` — check stdout/stderr.
- `docker exec -it <container> sh` — shell into running container.
- `docker compose logs -f` — stream all service logs.
- `docker inspect <container>` — check config, networking, mounts.
- `docker stats` — live resource usage (CPU, memory, network).
- `docker system df` — disk usage by images, containers, volumes.

$ARGUMENTS
