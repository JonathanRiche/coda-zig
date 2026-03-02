# coda_cli (Zig)

Small Zig CLI for **reading** data from Coda API v1.

## What it supports

- List docs
- List tables in a doc
- List views in a doc
- List rows in a table (works for board-style data too, since boards are table/view-backed)
- Optional `--json` output
- Pagination via `nextPageLink`

## Auth

Set your Coda API token:

```bash
export CODA_API_TOKEN="your-token"
```

Or pass it directly:

```bash
coda_cli --token your-token docs list
```

## Build

```bash
zig build
```

## Install (user-local)

Build and install into your user-local prefix:

```bash
zig build install -Doptimize=ReleaseFast --prefix "/home/rtg/.local"
```

Ensure `/home/rtg/.local/bin` is on your `PATH` so `coda_cli` is discoverable.

Optional shell alias:

```bash
alias coda='coda_cli'
```

## Run examples

```bash
# Print help
zig build run -- --help
zig build run -- -h

# List docs
zig build run -- docs list

# List tables for a doc
zig build run -- tables list --doc AbCDeFGH

# List views for a doc
zig build run -- views list --doc AbCDeFGH

# List rows for a table
zig build run -- rows list --doc AbCDeFGH --table grid-pqRstUv

# List rows with query + limit
zig build run -- rows list --doc AbCDeFGH --table grid-pqRstUv --query "Name:\"Launch\"" --limit 25

# JSON output
zig build run -- --json rows list --doc AbCDeFGH --table grid-pqRstUv
```

## Notes

- Endpoints used are from Coda API v1 (`/apis/v1`).
- This CLI is intentionally read-only.
- Human output is concise; use `--json` for scripting.
