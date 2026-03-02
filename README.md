# coda (Zig)

Small Zig CLI for Coda API v1 with broad coverage across read and mutation endpoints.

## Highlights

- Zig stdlib-first implementation
- Global auth and output mode (`--token`, `--json`)
- Reusable API client with GET/POST/PUT/DELETE helpers
- Pagination support for both `nextPageLink` and `nextPageToken`
- Human-readable output by default, raw JSON with `--json`
- Row upsert payload input from inline JSON (`--payload`) or file (`--file`)

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

### Pages

- `coda pages list --doc <docId>`
- `coda pages get --doc <docId> --page <pageIdOrName>`

### Tables

- `coda tables list --doc <docId>`
- `coda tables get --doc <docId> --table <tableIdOrName>`

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

# Mutation status by request id
zig build run -- mutations get --request req-abc123

# JSON output
zig build run -- --json rows list --doc AbCDeFGH --table grid-pqRstUv
```

## Notes

- Endpoints used are from Coda API v1 (`/apis/v1`).
- Some mutation-related endpoints can vary by account/tenant rollout; `controls set` uses a PUT-first, POST-fallback strategy.
- `rows upsert` payload shape is passed through as provided. The CLI does not enforce schema beyond requiring payload input.
- Human output is concise; use `--json` for scripting and full response details.
