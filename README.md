# coda (Zig)

Small Zig CLI for Coda API v1 with broad coverage across read and mutation endpoints.

Project links:

- GitHub: https://github.com/JonathanRiche/coda-zig
- Coda API v1 docs: https://coda.io/developers/apis/v1

## Highlights

- Zig stdlib-first implementation
- Global auth and output mode (`--token`, `--json`)
- Reusable API client with GET/POST/PUT/DELETE helpers
- Pagination support for both `nextPageLink` and `nextPageToken`
- Human-readable output by default, raw JSON with `--json`
- Row upsert payload input from inline JSON (`--payload`) or file (`--file`)
- Page creation and page body updates for canvas pages
- Coverage for docs/folders/pages/tables/rows/permissions/publishing/analytics/account/workspaces/domains

## Capability summary

What this CLI can do well:

- Create, update, delete, and copy docs
- Create, update, delete, export, and inspect pages
- Append or replace body content on existing canvas pages using `pages update`
- Read tables, views, columns, formulas, controls, permissions, analytics, and workspace metadata
- Insert, upsert, update, delete, and button-click rows in existing tables

Important limits:

- The `tables` resource is read-only in this CLI because Coda API v1 only documents `list` and `get` table endpoints
- There is no documented Coda API v1 endpoint for creating a table directly
- If you need a new doc with tables already present, create the doc from a `sourceDoc` template copy
- Page body writes are supported for canvas pages; the API docs do not document arbitrary block insertion outside `pages update`

## Page content writes

For existing canvas pages, the body update path is:

- `coda pages update --doc <docId> --page <pageIdOrName> --payload <json>`

The payload shape for page body updates is:

```json
{
  "contentUpdate": {
    "insertionMode": "append",
    "canvasContent": {
      "format": "markdown",
      "content": "# Heading\n\nBody text"
    }
  }
}
```

Notes:

- `insertionMode` is typically `append` or `replace`
- `canvasContent.format` is documented for `markdown` and `html`
- `canvasContent.content` is the body text to write
- `pages update` can also include metadata fields like `name`, `subtitle`, `iconName`, `imageUrl`, and `isHidden`
- `pages content` reads page elements, and `pages content-delete` deletes page content, but the write/update path is still `pages update`

Examples:

Append markdown to an existing page:

```bash
coda pages update \
  --doc AbCDeFGH \
  --page canvas-xyz123 \
  --payload '{
    "contentUpdate": {
      "insertionMode": "append",
      "canvasContent": {
        "format": "markdown",
        "content": "## New section\n\nThis text was appended by the API."
      }
    }
  }'
```

Replace an existing page body:

```bash
coda pages update \
  --doc AbCDeFGH \
  --page canvas-xyz123 \
  --payload '{
    "contentUpdate": {
      "insertionMode": "replace",
      "canvasContent": {
        "format": "markdown",
        "content": "# Replaced page\n\nOld content is removed."
      }
    }
  }'
```

Append HTML:

```bash
coda pages update \
  --doc AbCDeFGH \
  --page canvas-xyz123 \
  --payload '{
    "contentUpdate": {
      "insertionMode": "append",
      "canvasContent": {
        "format": "html",
        "content": "<p><b>Hello</b> from the API.</p>"
      }
    }
  }'
```

Markdown tables can be sent as markdown content, for example:

```bash
coda pages update \
  --doc AbCDeFGH \
  --page canvas-xyz123 \
  --payload '{
    "contentUpdate": {
      "insertionMode": "append",
      "canvasContent": {
        "format": "markdown",
        "content": "| Name | Status |\n|---|---|\n| Launch | Ready |"
      }
    }
  }'
```

This sends a markdown table into the page body. Coda API v1 does not document that this becomes a native Coda table object, so treat it as page content import rather than table creation.

Primary references:

- Update page: https://coda.io/developers/apis/v1#tag/Doc-Structure/operation/updatePage
- Create page: https://coda.io/developers/apis/v1#tag/Doc-Structure/operation/createPage
- Page endpoints announcement: https://connect.superhuman.com/t/more-powerful-page-endpoints-in-the-coda-api/44103

## Table creation limit

The CLI does not expose `tables create` because the Coda API v1 docs do not document a table creation endpoint.

What is supported:

- `tables list`
- `tables get`
- `rows upsert`
- `rows update`
- `rows delete`

If you need a doc to start with tables, use doc copy/template flow:

```bash
coda docs create --payload '{
  "title": "New doc from template",
  "sourceDoc": "AbCDeFGH"
}'
```

Reference:

- Create doc: https://coda.io/developers/apis/v1#tag/Docs/operation/createDoc
- Tables and views: https://coda.io/developers/apis/v1#tag/Tables-and-Views

## Auth

Set your Coda API token:

```bash
export CODA_API_TOKEN="your-token"
```

Or pass it directly:

```bash
coda --token your-token docs list
```

## Command catalog

Global flags are accepted anywhere in the command:

- `--token <token>`
- `--json` (alias: `-j`)

Help is available at three levels:

- `coda --help`
- `coda <resource> --help`
- `coda <resource> <action> --help`

### Common aliases

- `--doc-id` -> `--doc`
- `--table-id` -> `--table`
- `--view-id` -> `--view`
- `--row-id` -> `--row`
- `--filter` -> `--query`
- `--page-size` -> `--limit`

### Docs

- `coda docs list`
- `coda docs get --doc <docId>`
- `coda docs create --payload <json>`
- `coda docs update --doc <docId> --payload <json>`
- `coda docs delete --doc <docId>`

### Pages

- `coda pages list --doc <docId>`
- `coda pages get --doc <docId> --page <pageIdOrName>`
- `coda pages create --doc <docId> --payload <json>`
- `coda pages update --doc <docId> --page <pageIdOrName> --payload <json>`
- `coda pages delete --doc <docId> --page <pageIdOrName>`
- `coda pages content --doc <docId> --page <pageIdOrName>`
- `coda pages content-delete --doc <docId> --page <pageIdOrName>`
- `coda pages export --doc <docId> --page <pageIdOrName> --payload <json>`
- `coda pages export-status --doc <docId> --page <pageIdOrName> --request <requestId>`

Page-specific notes:

- `pages update` is the write path for both metadata changes and canvas page body updates
- Body updates are sent in `contentUpdate`
- Documented formats for page body updates are `markdown` and `html`

### Tables

- `coda tables list --doc <docId>`
- `coda tables get --doc <docId> --table <tableIdOrName>`

Table-specific notes:

- Table create/update/delete endpoints are not documented by Coda API v1
- Use `rows` commands to mutate data inside an existing table
- Use `docs create` with `sourceDoc` if you need a new doc that already contains tables

### Views

- `coda views list --doc <docId>`
- `coda views get --doc <docId> --view <viewIdOrName>`

### Columns

- `coda columns list --doc <docId> --table <tableIdOrName>`
- `coda columns get --doc <docId> --table <tableIdOrName> --column <columnIdOrName>`

### Rows

- `coda rows list --doc <docId> --table <tableIdOrName> [--query <query>] [--limit <n>]`
- `coda rows get --doc <docId> --table <tableIdOrName> --row <rowIdOrName>`
- `coda rows upsert --doc <docId> --table <tableIdOrName> --payload <json>`
- `coda rows upsert --doc <docId> --table <tableIdOrName> --file <path.json>`
- `coda rows delete --doc <docId> --table <tableIdOrName> --row <rowIdOrName>`
- `coda rows update --doc <docId> --table <tableIdOrName> --row <rowIdOrName> --payload <json>`
- `coda rows delete-many --doc <docId> --table <tableIdOrName> --payload <json>`
- `coda rows button --doc <docId> --table <tableIdOrName> --row <rowIdOrName> --column <columnIdOrName>`

### Formulas

- `coda formulas list --doc <docId>`
- `coda formulas get --doc <docId> --formula <formulaIdOrName>`

### Controls

- `coda controls list --doc <docId>`
- `coda controls get --doc <docId> --control <controlIdOrName>`
- `coda controls set --doc <docId> --control <controlIdOrName> --value <text>`
- `coda controls set --doc <docId> --control <controlIdOrName> --value-json <json>`

### Permissions

- `coda permissions list --doc <docId>`
- `coda permissions metadata --doc <docId>`
- `coda permissions add --doc <docId> --payload <json>`
- `coda permissions delete --doc <docId> --permission <permissionId>`
- `coda permissions principals --doc <docId> [--query <text>]`
- `coda permissions settings --doc <docId>`
- `coda permissions settings-update --doc <docId> --payload <json>`

### Folders

- `coda folders list`
- `coda folders create --payload <json>`
- `coda folders get --folder <folderId>`
- `coda folders update --folder <folderId> --payload <json>`
- `coda folders delete --folder <folderId>`

### Publishing

- `coda publish categories --doc <docId>`
- `coda publish set --doc <docId> --payload <json>`
- `coda publish unset --doc <docId>`

### Automations

- `coda automations trigger --doc <docId> --rule <ruleId> [--payload <json>]`

### Domains

- `coda domains list --doc <docId>`
- `coda domains add --doc <docId> --payload <json>`
- `coda domains update --doc <docId> --domain <customDomain> --payload <json>`
- `coda domains delete --doc <docId> --domain <customDomain>`
- `coda domains provider --domain <customDomain>`

### Account

- `coda account whoami`

### Analytics

- `coda analytics docs [--limit <n>]`
- `coda analytics doc-pages --doc <docId> [--limit <n>]`
- `coda analytics docs-summary`
- `coda analytics packs [--limit <n>]`
- `coda analytics packs-summary`
- `coda analytics pack-formulas --pack <packId> [--pack-formula-names <csv>] [--pack-formula-types <csv>]`
- `coda analytics updated`

### Resolve

- `coda resolve link --url <browserLink> [--degrade-gracefully <true|false>]`

### Workspaces

- `coda workspaces roles --workspace <workspaceId>`
- `coda workspaces users --workspace <workspaceId> [--included-roles <csv>]`
- `coda workspaces set-role --workspace <workspaceId> --payload <json>`

### Mutations

- `coda mutations get --request <requestId>`
- `coda mutations get --doc <docId> --mutation <mutationId>`

## Build

```bash
zig build
```

## Install (user-local)

Build and install into your user-local prefix:

```bash
zig build install -Doptimize=ReleaseFast --prefix "/home/rtg/.local"
```

Ensure `/home/rtg/.local/bin` is on your `PATH` so `coda` is discoverable.

## Run examples

```bash
# Print help
zig build run -- --help
zig build run -- -h
zig build run -- docs --help
zig build run -- rows list --help

# List docs
zig build run -- docs list

# Create a doc
zig build run -- docs create --payload '{"title":"API-created doc"}'

# Get a single doc
zig build run -- docs get --doc AbCDeFGH

# List pages for a doc
zig build run -- pages list --doc AbCDeFGH

# Get a single page
zig build run -- pages get --doc AbCDeFGH --page canvas-xyz123

# List tables for a doc
zig build run -- tables list --doc AbCDeFGH

# Get a single table
zig build run -- tables get --doc AbCDeFGH --table grid-pqRstUv

# List views for a doc
zig build run -- views list --doc AbCDeFGH

# Get a single view
zig build run -- views get --doc AbCDeFGH --view view-a1b2c3

# List columns for a table
zig build run -- columns list --doc AbCDeFGH --table grid-pqRstUv

# Get one column
zig build run -- columns get --doc AbCDeFGH --table grid-pqRstUv --column c-tuVwXy

# List rows for a table
zig build run -- rows list --doc AbCDeFGH --table grid-pqRstUv

# Get one row
zig build run -- rows get --doc AbCDeFGH --table grid-pqRstUv --row i-123456

# List rows with query + limit
zig build run -- rows list --doc AbCDeFGH --table grid-pqRstUv --query "Name:\"Launch\"" --limit 25

# Alias examples
zig build run -- rows list --doc-id AbCDeFGH --table-id grid-pqRstUv --filter "Status:\"Open\"" --page-size 10

# Upsert rows with inline JSON payload
zig build run -- rows upsert --doc AbCDeFGH --table grid-pqRstUv --payload '{"rows":[{"cells":[{"column":"Name","value":"Launch"}]}],"keyColumns":["Name"]}'

# Upsert rows from file
zig build run -- rows upsert --doc AbCDeFGH --table grid-pqRstUv --file ./payload.json

# Delete a row
zig build run -- rows delete --doc AbCDeFGH --table grid-pqRstUv --row i-123456

# List formulas
zig build run -- formulas list --doc AbCDeFGH

# List controls
zig build run -- controls list --doc AbCDeFGH

# Set control value with plain text
zig build run -- controls set --doc AbCDeFGH --control ctrl-a1b2 --value "Ready"

# Set control value with JSON value
zig build run -- controls set --doc AbCDeFGH --control ctrl-a1b2 --value-json '42'

# List permissions
zig build run -- permissions list --doc AbCDeFGH

# Get sharing metadata
zig build run -- permissions metadata --doc AbCDeFGH

# Publish a doc
zig build run -- publish set --doc AbCDeFGH --payload '{"mode":"view","discoverable":false}'

# Trigger an automation rule
zig build run -- automations trigger --doc AbCDeFGH --rule rule-a1b2

# Who am I (token owner)
zig build run -- account whoami

# Resolve a browser link
zig build run -- resolve link --url "https://coda.io/d/_dAbCDeFGH"

# Mutation status by request id
zig build run -- mutations get --request req-abc123

# JSON output
zig build run -- --json rows list --doc AbCDeFGH --table grid-pqRstUv
```

## Notes

- Endpoints used are from Coda API v1 (`/apis/v1`).
- Some mutation-related endpoints can vary by account/tenant rollout; `controls set` uses a PUT-first, POST-fallback strategy.
- `rows upsert` payload shape is passed through as provided. The CLI does not enforce schema beyond requiring payload input.
- `pages update` payloads are also passed through as provided, which allows `contentUpdate` for canvas page body writes.
- The CLI help output links to both the GitHub README and the Coda API docs for deeper reference.
- Human output is concise; use `--json` for scripting and full response details.
