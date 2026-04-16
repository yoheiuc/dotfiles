Design and document REST or GraphQL APIs. Generate OpenAPI specs when applicable.

## Workflow
1. **Clarify the domain**: what resources exist, how they relate, who consumes the API.
2. **Design the interface**: endpoints/operations, request/response shapes, error formats.
3. **Document**: generate OpenAPI 3.1 spec (REST) or schema (GraphQL).
4. **Validate**: check for consistency, naming conventions, and common pitfalls.

## REST API design principles

### Resources and URLs
- Use **nouns** for resources: `/users`, `/orders`, `/products`.
- Use **plural** consistently: `/users/123`, not `/user/123`.
- Nest for relationships: `/users/123/orders` (max 2 levels deep).
- Use query params for filtering/sorting: `/users?role=admin&sort=-created_at`.
- Avoid verbs in URLs: `/users/123/activate` -> `PATCH /users/123` with `{"status": "active"}`.

### HTTP methods
| Method | Purpose | Idempotent | Response |
|---|---|---|---|
| GET | Read | Yes | 200 + resource |
| POST | Create | No | 201 + created resource + Location header |
| PUT | Full replace | Yes | 200 + updated resource |
| PATCH | Partial update | Yes | 200 + updated resource |
| DELETE | Remove | Yes | 204 (no body) |

### Response format
```json
{
  "data": { ... },
  "meta": { "page": 1, "total": 42 }
}
```

### Error format (RFC 7807 Problem Details)
```json
{
  "type": "https://api.example.com/errors/not-found",
  "title": "Resource not found",
  "status": 404,
  "detail": "User with ID 123 does not exist"
}
```

### Status codes
- `200` OK — successful GET/PUT/PATCH
- `201` Created — successful POST
- `204` No Content — successful DELETE
- `400` Bad Request — validation error, malformed input
- `401` Unauthorized — missing or invalid auth
- `403` Forbidden — authenticated but not authorized
- `404` Not Found — resource doesn't exist
- `409` Conflict — resource state conflict (duplicate, version mismatch)
- `422` Unprocessable Entity — semantically invalid input
- `429` Too Many Requests — rate limited
- `500` Internal Server Error — unexpected failure

### Pagination
- Use cursor-based pagination for large datasets: `?cursor=abc&limit=20`.
- Offset-based (`?page=2&per_page=20`) is simpler but degrades on large datasets.
- Always include pagination metadata in response.

### Versioning
- URL prefix: `/v1/users` (simplest, most common).
- Header: `Accept: application/vnd.api+json;version=1` (cleaner URLs).
- Don't version until you need to break compatibility.

## GraphQL design principles
- **Schema-first**: design the schema before implementation.
- **Queries for reads, mutations for writes**: never change state in a query.
- **Input types**: use dedicated input types for mutations.
- **Connections for pagination**: use Relay-style cursor-based connections.
- **Error handling**: use union types for expected errors, top-level `errors` for unexpected.
- **N+1 prevention**: use DataLoader or equivalent batching.

## OpenAPI spec generation
When designing a REST API, produce an `openapi.yaml` (or `.json`) following OpenAPI 3.1:
- Include all endpoints, methods, request/response schemas.
- Define reusable schemas in `components/schemas`.
- Add examples for request bodies and responses.
- Document authentication in `components/securitySchemes`.
- Include error responses for each endpoint.

## Security considerations
- Use UUIDs for public resource IDs (not auto-incrementing integers).
- Rate limiting on all endpoints.
- Input validation at the API boundary.
- Authentication on every non-public endpoint.
- Authorization checks at the resource level (not just route level).
- CORS configuration for browser clients.
- Don't expose internal error details in production responses.

$ARGUMENTS
