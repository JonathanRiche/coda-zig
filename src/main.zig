//! Coda CLI with broad Coda API v1 endpoint coverage.
const std = @import("std");
const builtin = @import("builtin");

const BASE_URL = "https://coda.io/apis/v1";

const USAGE_TEXT =
    "Usage:\n" ++
    "  coda [--token <token>] [--json] docs list\n" ++
    "  coda [--token <token>] [--json] folders list\n" ++
    "  coda [--token <token>] [--json] tables list --doc <docId>\n" ++
    "  coda [--token <token>] [--json] views list --doc <docId>\n" ++
    "  coda [--token <token>] [--json] rows list --doc <docId> --table <tableIdOrName> [--query <query>] [--limit <n>]\n" ++
    "  coda [--token <token>] [--json] <resource> <action> --help\n" ++
    "  coda <resource> --help\n" ++
    "  coda <resource> <action> --help\n" ++
    "  coda --help\n" ++
    "  coda -h\n" ++
    "\n" ++
    "Global flags:\n" ++
    "  --token <token>  Coda API token\n" ++
    "  --json, -j       Render raw JSON output\n" ++
    "\n" ++
    "Env:\n" ++
    "  CODA_API_TOKEN  Coda API token (used if --token is not provided)\n";

const HELP_DOCS_TEXT =
    "Usage:\n" ++
    "  coda [--token <token>] [--json] docs list\n" ++
    "  coda [--token <token>] [--json] docs create (--payload <json> | --file <path>)\n" ++
    "  coda [--token <token>] [--json] docs get --doc <docId>\n" ++
    "  coda [--token <token>] [--json] docs update --doc <docId> (--payload <json> | --file <path>)\n" ++
    "  coda [--token <token>] [--json] docs delete --doc <docId>\n" ++
    "\n" ++
    "Aliases:\n" ++
    "  --doc-id  Alias of --doc\n";

const HELP_ROWS_TEXT =
    "Usage:\n" ++
    "  coda [--token <token>] [--json] rows list --doc <docId> --table <tableIdOrName> [--query <query>] [--limit <n>]\n" ++
    "  coda [--token <token>] [--json] rows get --doc <docId> --table <tableIdOrName> --row <rowIdOrName>\n" ++
    "  coda [--token <token>] [--json] rows upsert --doc <docId> --table <tableIdOrName> (--payload <json> | --file <path>)\n" ++
    "  coda [--token <token>] [--json] rows update --doc <docId> --table <tableIdOrName> --row <rowIdOrName> (--payload <json> | --file <path>)\n" ++
    "  coda [--token <token>] [--json] rows delete-many --doc <docId> --table <tableIdOrName> (--payload <json> | --file <path>)\n" ++
    "  coda [--token <token>] [--json] rows delete --doc <docId> --table <tableIdOrName> --row <rowIdOrName>\n" ++
    "  coda [--token <token>] [--json] rows button --doc <docId> --table <tableIdOrName> --row <rowIdOrName> --column <columnIdOrName>\n" ++
    "\n" ++
    "Aliases:\n" ++
    "  --doc-id, --table-id, --row-id\n" ++
    "  --filter (alias of --query), --page-size (alias of --limit)\n";

const CliError = error{
    Usage,
    MissingToken,
    MissingValue,
    MissingFlag,
    InvalidLimit,
    InvalidBoolean,
    MalformedJson,
    InvalidResponse,
    HttpError,
};

const GlobalOptions = struct {
    token: ?[]const u8 = null,
    json: bool = false,
};

const HelpSelection = struct {
    resource: ?[]const u8,
    action: ?[]const u8,
};

const ResolvedToken = struct {
    value: []const u8,
    owned: bool,

    fn deinit(self: ResolvedToken, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.value);
    }
};

const ApiResponse = struct {
    body: []u8,
    status: std.http.Status,

    fn deinit(self: ApiResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

const ApiClient = struct {
    allocator: std.mem.Allocator,
    token: []const u8,

    fn get(self: ApiClient, path_or_url: []const u8) !ApiResponse {
        return self.request(.GET, path_or_url, null);
    }

    fn post(self: ApiClient, path_or_url: []const u8, body: []const u8) !ApiResponse {
        return self.request(.POST, path_or_url, body);
    }

    fn put(self: ApiClient, path_or_url: []const u8, body: []const u8) !ApiResponse {
        return self.request(.PUT, path_or_url, body);
    }

    fn patch(self: ApiClient, path_or_url: []const u8, body: []const u8) !ApiResponse {
        return self.request(.PATCH, path_or_url, body);
    }

    fn delete(self: ApiClient, path_or_url: []const u8) !ApiResponse {
        return self.request(.DELETE, path_or_url, null);
    }

    fn request(self: ApiClient, method: std.http.Method, path_or_url: []const u8, body: ?[]const u8) !ApiResponse {
        var client: std.http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        const full_url = try buildUrl(self.allocator, path_or_url);
        defer self.allocator.free(full_url);

        const auth = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.token});
        defer self.allocator.free(auth);

        var writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer writer.deinit();

        const result = if (body) |payload| blk: {
            const headers = [_]std.http.Header{
                .{ .name = "authorization", .value = auth },
                .{ .name = "accept", .value = "application/json" },
                .{ .name = "content-type", .value = "application/json" },
            };
            break :blk try client.fetch(.{
                .location = .{ .url = full_url },
                .method = method,
                .payload = payload,
                .extra_headers = &headers,
                .response_writer = &writer.writer,
            });
        } else blk: {
            const headers = [_]std.http.Header{
                .{ .name = "authorization", .value = auth },
                .{ .name = "accept", .value = "application/json" },
            };
            break :blk try client.fetch(.{
                .location = .{ .url = full_url },
                .method = method,
                .extra_headers = &headers,
                .response_writer = &writer.writer,
            });
        };

        if (@intFromEnum(result.status) >= 400) {
            printApiError(result.status, writer.written());
            return CliError.HttpError;
        }

        return .{ .body = try writer.toOwnedSlice(), .status = result.status };
    }
};

const PagedItems = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(std.json.Value),

    fn deinit(self: *PagedItems) void {
        self.items.deinit(self.arena.allocator());
        self.arena.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const exit_code = run(allocator) catch |err| handleCliError(err);
    if (exit_code != 0) std.process.exit(exit_code);
}

fn run(allocator: std.mem.Allocator) !u8 {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        printUsageStdout();
        return 0;
    }

    const parsed = try parseCommandLine(allocator, args);
    defer allocator.free(parsed.positionals);

    if (parsed.positionals.len == 0) {
        printUsageStdout();
        return 0;
    }

    if (helpTarget(parsed.positionals)) |target| {
        printHelp(target);
        return 0;
    }

    if (parsed.positionals.len < 2) return CliError.Usage;

    const resource = parsed.positionals[0];
    const action = parsed.positionals[1];
    const cmd_args = parsed.positionals;
    const cmd_start: usize = 2;

    const resolved_token = try resolveToken(parsed.opts, allocator);
    defer resolved_token.deinit(allocator);

    const api: ApiClient = .{ .allocator = allocator, .token = resolved_token.value };

    if (std.mem.eql(u8, resource, "docs")) {
        try cmdDocs(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "folders")) {
        try cmdFolders(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "pages")) {
        try cmdPages(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "tables")) {
        try cmdTables(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "views")) {
        try cmdViews(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "columns")) {
        try cmdColumns(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "rows")) {
        try cmdRows(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "formulas")) {
        try cmdFormulas(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "controls")) {
        try cmdControls(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "permissions")) {
        try cmdPermissions(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "mutations")) {
        try cmdMutations(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "publish")) {
        try cmdPublish(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "automations")) {
        try cmdAutomations(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "account")) {
        try cmdAccount(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "analytics")) {
        try cmdAnalytics(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "resolve")) {
        try cmdResolve(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "domains")) {
        try cmdDomains(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }
    if (std.mem.eql(u8, resource, "workspaces")) {
        try cmdWorkspaces(allocator, api, action, cmd_args, cmd_start, parsed.opts.json);
        return 0;
    }

    return CliError.Usage;
}

fn cmdDocs(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--is-owner", "--is-published", "--query", "--source-doc", "--is-starred", "--in-gallery", "--workspace", "--workspace-id", "--folder", "--folder-id", "--limit", "--page-size" });
        const is_owner = try optionalFlag(args, "--is-owner", start);
        const is_published = try optionalFlag(args, "--is-published", start);
        const query = try optionalFlag(args, "--query", start);
        const source_doc = try optionalFlag(args, "--source-doc", start);
        const is_starred = try optionalFlag(args, "--is-starred", start);
        const in_gallery = try optionalFlag(args, "--in-gallery", start);
        const workspace = try optionalFlagAny(args, &.{ "--workspace", "--workspace-id" }, start);
        const folder = try optionalFlagAny(args, &.{ "--folder", "--folder-id" }, start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);

        if (is_owner) |value| _ = try parseBoolean(value, "--is-owner");
        if (is_published) |value| _ = try parseBoolean(value, "--is-published");
        if (is_starred) |value| _ = try parseBoolean(value, "--is-starred");
        if (in_gallery) |value| _ = try parseBoolean(value, "--in-gallery");
        if (limit) |value| {
            _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        }

        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (is_owner) |value| try appendParam(allocator, &params, "isOwner", value);
        if (is_published) |value| try appendParam(allocator, &params, "isPublished", value);
        if (query) |value| try appendParam(allocator, &params, "query", value);
        if (source_doc) |value| try appendParam(allocator, &params, "sourceDoc", value);
        if (is_starred) |value| try appendParam(allocator, &params, "isStarred", value);
        if (in_gallery) |value| try appendParam(allocator, &params, "inGallery", value);
        if (workspace) |value| try appendParam(allocator, &params, "workspaceId", value);
        if (folder) |value| try appendParam(allocator, &params, "folderId", value);
        if (limit) |value| try appendParam(allocator, &params, "limit", value);

        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/docs{s}{s}", .{ prefix, params.items });
        defer allocator.free(path);

        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "create")) {
        try ensureSupportedFlags(args, start, &.{ "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        var response = try api.post("/docs", body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}", .{doc});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "update")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}", .{doc});
        defer allocator.free(path);
        var response = try api.patch(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}", .{doc});
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdFolders(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--workspace", "--workspace-id", "--is-starred", "--limit", "--page-size" });
        const workspace = try optionalFlagAny(args, &.{ "--workspace", "--workspace-id" }, start);
        const is_starred = try optionalFlag(args, "--is-starred", start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);

        if (is_starred) |value| _ = try parseBoolean(value, "--is-starred");
        if (limit) |value| {
            _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        }

        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (workspace) |value| try appendParam(allocator, &params, "workspaceId", value);
        if (is_starred) |value| try appendParam(allocator, &params, "isStarred", value);
        if (limit) |value| try appendParam(allocator, &params, "limit", value);

        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/folders{s}{s}", .{ prefix, params.items });
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "create")) {
        try ensureSupportedFlags(args, start, &.{ "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        var response = try api.post("/folders", body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--folder", "--folder-id" });
        const folder = try requireFlagAny(args, &.{ "--folder", "--folder-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/folders/{s}", .{folder});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "update")) {
        try ensureSupportedFlags(args, start, &.{ "--folder", "--folder-id", "--payload", "--file" });
        const folder = try requireFlagAny(args, &.{ "--folder", "--folder-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/folders/{s}", .{folder});
        defer allocator.free(path);
        var response = try api.patch(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--folder", "--folder-id" });
        const folder = try requireFlagAny(args, &.{ "--folder", "--folder-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/folders/{s}", .{folder});
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdPages(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages", .{doc});
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}", .{ doc, page });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "create")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages", .{doc});
        defer allocator.free(path);
        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "update")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id", "--payload", "--file" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}", .{ doc, page });
        defer allocator.free(path);
        var response = try api.put(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}", .{ doc, page });
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "content")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}/content", .{ doc, page });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "content-delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}/content", .{ doc, page });
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "export")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id", "--payload", "--file" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}/export", .{ doc, page });
        defer allocator.free(path);
        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "export-status")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--page", "--page-id", "--request", "--request-id" });
        const page = try requireFlagAny(args, &.{ "--page", "--page-id" }, start);
        const request_id = try requireFlagAny(args, &.{ "--request", "--request-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/pages/{s}/export/{s}", .{ doc, page, request_id });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdTables(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables", .{doc});
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--use-updated-table-layouts" });
        const table = try requireFlagAny(args, &.{ "--table", "--table-id" }, start);
        const use_updated_table_layouts = try optionalFlag(args, "--use-updated-table-layouts", start);
        if (use_updated_table_layouts) |value| _ = try parseBoolean(value, "--use-updated-table-layouts");
        const suffix = if (use_updated_table_layouts) |value|
            try std.fmt.allocPrint(allocator, "?useUpdatedTableLayouts={s}", .{value})
        else
            try allocator.dupe(u8, "");
        defer allocator.free(suffix);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}{s}", .{ doc, table, suffix });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdViews(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/views", .{doc});
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--view", "--view-id" });
        const view = try requireFlagAny(args, &.{ "--view", "--view-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/views/{s}", .{ doc, view });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdColumns(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    const table = try requireFlagAny(args, &.{ "--table", "--table-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--limit", "--page-size", "--visible-only" });
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        const visible_only = try optionalFlag(args, "--visible-only", start);
        if (limit) |value| _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        if (visible_only) |value| _ = try parseBoolean(value, "--visible-only");
        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (limit) |value| try appendParam(allocator, &params, "limit", value);
        if (visible_only) |value| try appendParam(allocator, &params, "visibleOnly", value);
        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/columns{s}{s}", .{ doc, table, prefix, params.items });
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--column", "--column-id" });
        const column = try requireFlagAny(args, &.{ "--column", "--column-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/columns/{s}", .{ doc, table, column });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdRows(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    const table = try requireFlagAny(args, &.{ "--table", "--table-id" }, start);

    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--query", "--filter", "--limit", "--page-size", "--use-column-names", "--value-format", "--visible-only", "--sort-by" });
        const query = try optionalFlagAny(args, &.{ "--query", "--filter" }, start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        const use_column_names = try optionalFlag(args, "--use-column-names", start);
        const value_format = try optionalFlag(args, "--value-format", start);
        const visible_only = try optionalFlag(args, "--visible-only", start);
        const sort_by = try optionalFlag(args, "--sort-by", start);
        if (limit) |value| {
            _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        }
        if (use_column_names) |value| _ = try parseBoolean(value, "--use-column-names");
        if (visible_only) |value| _ = try parseBoolean(value, "--visible-only");

        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (query) |q| {
            try appendParam(allocator, &params, "query", q);
        }
        if (limit) |l| {
            try appendParam(allocator, &params, "limit", l);
        }
        if (use_column_names) |value| {
            try appendParam(allocator, &params, "useColumnNames", value);
        }
        if (value_format) |value| {
            try appendParam(allocator, &params, "valueFormat", value);
        }
        if (visible_only) |value| {
            try appendParam(allocator, &params, "visibleOnly", value);
        }
        if (sort_by) |value| {
            try appendParam(allocator, &params, "sortBy", value);
        }

        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows{s}{s}", .{ doc, table, prefix, params.items });
        defer allocator.free(path);

        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }

    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--row", "--row-id", "--use-column-names", "--value-format" });
        const row = try requireFlagAny(args, &.{ "--row", "--row-id" }, start);
        const use_column_names = try optionalFlag(args, "--use-column-names", start);
        const value_format = try optionalFlag(args, "--value-format", start);
        if (use_column_names) |value| _ = try parseBoolean(value, "--use-column-names");

        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (use_column_names) |value| {
            try appendParam(allocator, &params, "useColumnNames", value);
        }
        if (value_format) |value| {
            try appendParam(allocator, &params, "valueFormat", value);
        }

        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows/{s}{s}{s}", .{ doc, table, row, prefix, params.items });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }

    if (std.mem.eql(u8, action, "upsert")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--payload", "--file", "--disable-parsing" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const disable_parsing = try optionalFlag(args, "--disable-parsing", start);
        if (disable_parsing) |value| _ = try parseBoolean(value, "--disable-parsing");

        const prefix = if (disable_parsing != null) "?disableParsing=" else "";
        const suffix = disable_parsing orelse "";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows{s}{s}", .{ doc, table, prefix, suffix });
        defer allocator.free(path);

        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }

    if (std.mem.eql(u8, action, "update")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--row", "--row-id", "--payload", "--file", "--disable-parsing" });
        const row = try requireFlagAny(args, &.{ "--row", "--row-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const disable_parsing = try optionalFlag(args, "--disable-parsing", start);
        if (disable_parsing) |value| _ = try parseBoolean(value, "--disable-parsing");

        const prefix = if (disable_parsing != null) "?disableParsing=" else "";
        const suffix = disable_parsing orelse "";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows/{s}{s}{s}", .{ doc, table, row, prefix, suffix });
        defer allocator.free(path);
        var response = try api.put(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }

    if (std.mem.eql(u8, action, "delete-many")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows", .{ doc, table });
        defer allocator.free(path);
        var response = try api.request(.DELETE, path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }

    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--row", "--row-id" });
        const row = try requireFlagAny(args, &.{ "--row", "--row-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows/{s}", .{ doc, table, row });
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        if (response.body.len == 0) {
            printStdout("Row deleted.\n", .{});
        } else {
            try renderRawJsonBody(allocator, response.body, json_mode);
        }
        return;
    }

    if (std.mem.eql(u8, action, "button")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--table", "--table-id", "--row", "--row-id", "--column", "--column-id" });
        const row = try requireFlagAny(args, &.{ "--row", "--row-id" }, start);
        const column = try requireFlagAny(args, &.{ "--column", "--column-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/tables/{s}/rows/{s}/buttons/{s}", .{ doc, table, row, column });
        defer allocator.free(path);
        var response = try api.post(path, "{}");
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }

    return CliError.Usage;
}

fn cmdFormulas(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/formulas", .{doc});
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--formula", "--formula-id" });
        const formula = try requireFlagAny(args, &.{ "--formula", "--formula-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/formulas/{s}", .{ doc, formula });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdControls(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/controls", .{doc});
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "get")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--control", "--control-id" });
        const control = try requireFlagAny(args, &.{ "--control", "--control-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/controls/{s}", .{ doc, control });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "set")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--control", "--control-id", "--value", "--value-json" });
        const control = try requireFlagAny(args, &.{ "--control", "--control-id" }, start);
        const value = try optionalFlag(args, "--value", start);
        const value_json = try optionalFlag(args, "--value-json", start);
        const body = try controlSetBody(allocator, value, value_json);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/controls/{s}", .{ doc, control });
        defer allocator.free(path);

        var response = api.put(path, body) catch |put_err| {
            if (put_err == CliError.HttpError) {
                const fallback = try std.fmt.allocPrint(allocator, "/docs/{s}/controls/{s}/value", .{ doc, control });
                defer allocator.free(fallback);
                var fallback_response = try api.post(fallback, body);
                defer fallback_response.deinit(allocator);
                try renderRawJsonBody(allocator, fallback_response.body, json_mode);
                return;
            }
            return put_err;
        };
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdPermissions(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "metadata")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/metadata", .{doc});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--limit", "--page-size" });
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| {
            _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        }

        const path = if (limit) |value|
            try std.fmt.allocPrint(allocator, "/docs/{s}/acl/permissions?limit={s}", .{ doc, value })
        else
            try std.fmt.allocPrint(allocator, "/docs/{s}/acl/permissions", .{doc});
        defer allocator.free(path);

        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "add")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/permissions", .{doc});
        defer allocator.free(path);
        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--permission", "--permission-id" });
        const permission = try requireFlagAny(args, &.{ "--permission", "--permission-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/permissions/{s}", .{ doc, permission });
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "principals")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--query", "--limit", "--page-size" });
        const query = try optionalFlag(args, "--query", start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| {
            _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        }
        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (query) |value| try appendParam(allocator, &params, "query", value);
        if (limit) |value| try appendParam(allocator, &params, "limit", value);
        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/principals/search{s}{s}", .{ doc, prefix, params.items });
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "settings")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/settings", .{doc});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "settings-update")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/acl/settings", .{doc});
        defer allocator.free(path);
        var response = try api.patch(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdMutations(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (!std.mem.eql(u8, action, "get")) return CliError.Usage;
    try ensureSupportedFlags(args, start, &.{ "--request", "--request-id", "--doc", "--doc-id", "--mutation", "--mutation-id" });

    const request_id = try optionalFlagAny(args, &.{ "--request", "--request-id" }, start);
    const mutation_id = try optionalFlagAny(args, &.{ "--mutation", "--mutation-id" }, start);
    const doc = try optionalFlagAny(args, &.{ "--doc", "--doc-id" }, start);

    if (request_id != null and mutation_id != null) {
        printStderr("Use either --request or --mutation, not both.\n", .{});
        return CliError.Usage;
    }

    if (request_id) |rid| {
        const path = try std.fmt.allocPrint(allocator, "/mutationStatus/{s}", .{rid});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }

    if (mutation_id) |mid| {
        if (doc == null) {
            printStderr("Missing required flag: --doc (needed with --mutation)\n", .{});
            return CliError.MissingFlag;
        }
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/mutations/{s}", .{ doc.?, mid });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }

    printStderr("Missing required flag: --request or --mutation\n", .{});
    return CliError.MissingFlag;
}

fn cmdPublish(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    if (std.mem.eql(u8, action, "categories")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        try getAndRenderOne(allocator, api, "/categories", json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "set")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/publish", .{doc});
        defer allocator.free(path);
        var response = try api.put(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "unset")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/publish", .{doc});
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdAutomations(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (!std.mem.eql(u8, action, "trigger")) return CliError.Usage;
    try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--rule", "--rule-id", "--payload", "--file" });
    const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
    const rule = try requireFlagAny(args, &.{ "--rule", "--rule-id" }, start);
    const body = (readPayload(allocator, args, start) catch |err| switch (err) {
        CliError.MissingFlag => try allocator.dupe(u8, "{}"),
        else => return err,
    });
    defer allocator.free(body);
    const path = try std.fmt.allocPrint(allocator, "/docs/{s}/hooks/automation/{s}", .{ doc, rule });
    defer allocator.free(path);
    var response = try api.post(path, body);
    defer response.deinit(allocator);
    try renderRawJsonBody(allocator, response.body, json_mode);
}

fn cmdAccount(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (!std.mem.eql(u8, action, "whoami")) return CliError.Usage;
    try ensureSupportedFlags(args, start, &.{});
    try getAndRenderOne(allocator, api, "/whoami", json_mode);
}

fn cmdAnalytics(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (std.mem.eql(u8, action, "docs")) {
        try ensureSupportedFlags(args, start, &.{ "--limit", "--page-size" });
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        const path = if (limit) |value|
            try std.fmt.allocPrint(allocator, "/analytics/docs?limit={s}", .{value})
        else
            try allocator.dupe(u8, "/analytics/docs");
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "doc-pages")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--limit", "--page-size" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        const suffix = if (limit) |value| try std.fmt.allocPrint(allocator, "?limit={s}", .{value}) else try allocator.dupe(u8, "");
        defer allocator.free(suffix);
        const path = try std.fmt.allocPrint(allocator, "/analytics/docs/{s}/pages{s}", .{ doc, suffix });
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "docs-summary")) {
        try ensureSupportedFlags(args, start, &.{});
        try getAndRenderOne(allocator, api, "/analytics/docs/summary", json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "packs")) {
        try ensureSupportedFlags(args, start, &.{ "--limit", "--page-size" });
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        const path = if (limit) |value|
            try std.fmt.allocPrint(allocator, "/analytics/packs?limit={s}", .{value})
        else
            try allocator.dupe(u8, "/analytics/packs");
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "packs-summary")) {
        try ensureSupportedFlags(args, start, &.{});
        try getAndRenderOne(allocator, api, "/analytics/packs/summary", json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "pack-formulas")) {
        try ensureSupportedFlags(args, start, &.{ "--pack", "--pack-id", "--pack-formula-names", "--pack-formula-types", "--limit", "--page-size" });
        const pack = try requireFlagAny(args, &.{ "--pack", "--pack-id" }, start);
        const names = try optionalFlag(args, "--pack-formula-names", start);
        const types = try optionalFlag(args, "--pack-formula-types", start);
        const limit = try optionalFlagAny(args, &.{ "--limit", "--page-size" }, start);
        if (limit) |value| _ = std.fmt.parseInt(usize, value, 10) catch return CliError.InvalidLimit;
        var params: std.ArrayList(u8) = .empty;
        defer params.deinit(allocator);
        if (names) |value| try appendParam(allocator, &params, "packFormulaNames", value);
        if (types) |value| try appendParam(allocator, &params, "packFormulaTypes", value);
        if (limit) |value| try appendParam(allocator, &params, "limit", value);
        const prefix = if (params.items.len == 0) "" else "?";
        const path = try std.fmt.allocPrint(allocator, "/analytics/packs/{s}/formulas{s}{s}", .{ pack, prefix, params.items });
        defer allocator.free(path);
        var data = try fetchPaginatedItems(allocator, api, path);
        defer data.deinit();
        try renderList(data.items.items, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "updated")) {
        try ensureSupportedFlags(args, start, &.{});
        try getAndRenderOne(allocator, api, "/analytics/updated", json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdResolve(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (!std.mem.eql(u8, action, "link")) return CliError.Usage;
    try ensureSupportedFlags(args, start, &.{ "--url", "--degrade-gracefully" });
    const url = try requireFlag(args, "--url", start);
    const degrade = try optionalFlag(args, "--degrade-gracefully", start);
    if (degrade) |value| _ = try parseBoolean(value, "--degrade-gracefully");
    var params: std.ArrayList(u8) = .empty;
    defer params.deinit(allocator);
    try appendParam(allocator, &params, "url", url);
    if (degrade) |value| try appendParam(allocator, &params, "degradeGracefully", value);
    const path = try std.fmt.allocPrint(allocator, "/resolveBrowserLink?{s}", .{params.items});
    defer allocator.free(path);
    try getAndRenderOne(allocator, api, path, json_mode);
}

fn cmdDomains(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    if (std.mem.eql(u8, action, "list")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/domains", .{doc});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "add")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--payload", "--file" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/domains", .{doc});
        defer allocator.free(path);
        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "update")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--domain", "--payload", "--file" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const domain = try requireFlag(args, "--domain", start);
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/domains/{s}", .{ doc, domain });
        defer allocator.free(path);
        var response = try api.patch(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "delete")) {
        try ensureSupportedFlags(args, start, &.{ "--doc", "--doc-id", "--domain" });
        const doc = try requireFlagAny(args, &.{ "--doc", "--doc-id" }, start);
        const domain = try requireFlag(args, "--domain", start);
        const path = try std.fmt.allocPrint(allocator, "/docs/{s}/domains/{s}", .{ doc, domain });
        defer allocator.free(path);
        var response = try api.delete(path);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "provider")) {
        try ensureSupportedFlags(args, start, &.{"--domain"});
        const domain = try requireFlag(args, "--domain", start);
        const path = try std.fmt.allocPrint(allocator, "/domains/provider/{s}", .{domain});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    return CliError.Usage;
}

fn cmdWorkspaces(allocator: std.mem.Allocator, api: ApiClient, action: []const u8, args: []const []const u8, start: usize, json_mode: bool) !void {
    const workspace = try requireFlagAny(args, &.{ "--workspace", "--workspace-id" }, start);
    if (std.mem.eql(u8, action, "roles")) {
        try ensureSupportedFlags(args, start, &.{ "--workspace", "--workspace-id" });
        const path = try std.fmt.allocPrint(allocator, "/workspaces/{s}/roles", .{workspace});
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "users")) {
        try ensureSupportedFlags(args, start, &.{ "--workspace", "--workspace-id", "--included-roles" });
        const included_roles = try optionalFlag(args, "--included-roles", start);
        const suffix = if (included_roles) |value| try std.fmt.allocPrint(allocator, "?includedRoles={s}", .{value}) else try allocator.dupe(u8, "");
        defer allocator.free(suffix);
        const path = try std.fmt.allocPrint(allocator, "/workspaces/{s}/users{s}", .{ workspace, suffix });
        defer allocator.free(path);
        try getAndRenderOne(allocator, api, path, json_mode);
        return;
    }
    if (std.mem.eql(u8, action, "set-role")) {
        try ensureSupportedFlags(args, start, &.{ "--workspace", "--workspace-id", "--payload", "--file" });
        const body = try readPayload(allocator, args, start);
        defer allocator.free(body);
        const path = try std.fmt.allocPrint(allocator, "/workspaces/{s}/users/role", .{workspace});
        defer allocator.free(path);
        var response = try api.post(path, body);
        defer response.deinit(allocator);
        try renderRawJsonBody(allocator, response.body, json_mode);
        return;
    }
    return CliError.Usage;
}

fn fetchPaginatedItems(allocator: std.mem.Allocator, api: ApiClient, first_path_or_url: []const u8) !PagedItems {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    var all: std.ArrayList(std.json.Value) = .empty;
    errdefer all.deinit(arena_allocator);

    var current = try arena_allocator.dupe(u8, first_path_or_url);
    const token_base = try arena_allocator.dupe(u8, first_path_or_url);

    while (true) {
        var response = try api.get(current);
        defer response.deinit(allocator);

        const parsed = try std.json.parseFromSlice(std.json.Value, arena_allocator, response.body, .{});
        const root = parsed.value;
        if (root != .object) return CliError.InvalidResponse;

        if (root.object.get("items")) |items| {
            if (items != .array) return CliError.InvalidResponse;
            for (items.array.items) |item| {
                try all.append(arena_allocator, item);
            }
        } else {
            return CliError.InvalidResponse;
        }

        if (jsonString(root, "nextPageLink")) |next_link| {
            if (next_link.len > 0) {
                current = try arena_allocator.dupe(u8, next_link);
                continue;
            }
        }

        if (jsonString(root, "nextPageToken")) |next_token| {
            if (next_token.len > 0) {
                current = try appendQueryParam(arena_allocator, token_base, "pageToken", next_token);
                continue;
            }
        }

        break;
    }

    return .{ .arena = arena, .items = all };
}

fn getAndRenderOne(allocator: std.mem.Allocator, api: ApiClient, path: []const u8, json_mode: bool) !void {
    var response = try api.get(path);
    defer response.deinit(allocator);
    try renderRawJsonBody(allocator, response.body, json_mode);
}

fn renderRawJsonBody(allocator: std.mem.Allocator, body: []const u8, json_mode: bool) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try renderOne(parsed.value, json_mode);
}

fn renderList(items: []std.json.Value, json_mode: bool) !void {
    if (json_mode) {
        printStdout("{f}\n", .{std.json.fmt(items, .{ .whitespace = .indent_2 })});
        return;
    }
    if (items.len == 0) {
        printStdout("(no results)\n", .{});
        return;
    }
    for (items) |item| {
        const id = jsonString(item, "id") orelse "n/a";
        const label = displayLabel(item);
        if (label.len > 0) {
            printStdout("- {s} [{s}]\n", .{ label, id });
        } else {
            printStdout("- [{s}]\n", .{id});
        }
    }
}

fn renderOne(value: std.json.Value, json_mode: bool) !void {
    if (json_mode) {
        printStdout("{f}\n", .{std.json.fmt(value, .{ .whitespace = .indent_2 })});
        return;
    }

    if (value == .object) {
        const id = jsonString(value, "id") orelse "";
        const label = displayLabel(value);
        if (label.len > 0 and id.len > 0) {
            printStdout("{s} [{s}]\n", .{ label, id });
            return;
        }
        if (id.len > 0) {
            printStdout("[{s}]\n", .{id});
            return;
        }
    }

    printStdout("{f}\n", .{std.json.fmt(value, .{ .whitespace = .indent_2 })});
}

fn displayLabel(value: std.json.Value) []const u8 {
    return jsonString(value, "name") orelse jsonString(value, "displayName") orelse jsonString(value, "title") orelse "";
}

fn buildUrl(allocator: std.mem.Allocator, path_or_url: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, path_or_url, "https://") or std.mem.startsWith(u8, path_or_url, "http://")) {
        return allocator.dupe(u8, path_or_url);
    }
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ BASE_URL, path_or_url });
}

fn appendParam(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: []const u8) !void {
    if (out.items.len > 0) try out.append(allocator, '&');
    try out.writer(allocator).print("{s}={s}", .{ key, value });
}

fn appendQueryParam(allocator: std.mem.Allocator, url: []const u8, key: []const u8, value: []const u8) ![]u8 {
    const sep = if (std.mem.indexOfScalar(u8, url, '?') != null) "&" else "?";
    return std.fmt.allocPrint(allocator, "{s}{s}{s}={s}", .{ url, sep, key, value });
}

fn readPayload(allocator: std.mem.Allocator, args: []const []const u8, start: usize) ![]u8 {
    const payload = try optionalFlag(args, "--payload", start);
    const file = try optionalFlag(args, "--file", start);

    if (payload != null and file != null) {
        printStderr("Provide either --payload or --file, not both.\n", .{});
        return CliError.Usage;
    }
    if (payload) |inline_payload| {
        try ensureValidJson(inline_payload, "--payload");
        return allocator.dupe(u8, inline_payload);
    }
    if (file) |path| {
        const body = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 8);
        errdefer allocator.free(body);
        try ensureValidJson(body, "--file");
        return body;
    }

    printStderr("Missing payload: provide --payload <json> or --file <path>.\n", .{});
    return CliError.MissingFlag;
}

fn controlSetBody(allocator: std.mem.Allocator, value: ?[]const u8, value_json: ?[]const u8) ![]u8 {
    if (value != null and value_json != null) {
        printStderr("Provide either --value or --value-json, not both.\n", .{});
        return CliError.Usage;
    }
    if (value) |raw| {
        const body: struct { value: []const u8 } = .{ .value = raw };
        return std.json.Stringify.valueAlloc(allocator, body, .{});
    }
    if (value_json) |raw_json| {
        try ensureValidJson(raw_json, "--value-json");
        return std.fmt.allocPrint(allocator, "{{\"value\":{s}}}", .{raw_json});
    }

    printStderr("Missing value: provide --value <text> or --value-json <json>.\n", .{});
    return CliError.MissingFlag;
}

fn ensureValidJson(raw: []const u8, source_flag: []const u8) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, raw, .{}) catch {
        printStderr("Malformed JSON passed to {s}.\n", .{source_flag});
        return CliError.MalformedJson;
    };
    parsed.deinit();
}

fn parseBoolean(raw: []const u8, flag_name: []const u8) !bool {
    if (std.mem.eql(u8, raw, "true")) return true;
    if (std.mem.eql(u8, raw, "false")) return false;
    printStderr("Invalid value for {s}; expected true or false.\n", .{flag_name});
    return CliError.InvalidBoolean;
}

fn handleCliError(err: anyerror) u8 {
    switch (err) {
        CliError.Usage => {
            printStderr("Invalid command or arguments.\n", .{});
            printUsageStderr();
            return 2;
        },
        CliError.MissingToken => {
            printStderr("Missing API token. Set CODA_API_TOKEN or pass --token <token>.\n", .{});
            return 2;
        },
        CliError.MissingValue, CliError.MissingFlag => {
            printUsageStderr();
            return 2;
        },
        CliError.InvalidLimit => {
            printStderr("Invalid value for --limit; expected an integer.\n", .{});
            return 2;
        },
        CliError.InvalidBoolean => {
            return 2;
        },
        CliError.MalformedJson => {
            return 2;
        },
        CliError.InvalidResponse => {
            printStderr("Received an invalid response from Coda API.\n", .{});
            return 1;
        },
        CliError.HttpError => return 1,
        else => {
            printStderr("Unexpected error: {s}\n", .{@errorName(err)});
            return 1;
        },
    }
}

fn printApiError(status: std.http.Status, body: []const u8) void {
    printStderr("API request failed with status {d}.\n", .{@intFromEnum(status)});
    if (body.len == 0) return;

    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch {
        printStderr("{s}\n", .{body});
        return;
    };
    defer parsed.deinit();

    if (jsonString(parsed.value, "message")) |message| {
        printStderr("{s}\n", .{message});
        return;
    }
    if (jsonString(parsed.value, "error")) |message| {
        printStderr("{s}\n", .{message});
        return;
    }

    printStderr("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
}

fn parseCommandLine(allocator: std.mem.Allocator, args: []const []const u8) !struct { opts: GlobalOptions, positionals: []const []const u8 } {
    var opts: GlobalOptions = .{};
    var positionals: std.ArrayList([]const u8) = .empty;
    errdefer positionals.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            opts.json = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--token")) {
            if (i + 1 >= args.len or isFlagLike(args[i + 1])) {
                printStderr("Missing value for --token.\n", .{});
                return CliError.MissingValue;
            }
            opts.token = args[i + 1];
            i += 1;
            continue;
        }
        try positionals.append(allocator, arg);
    }

    return .{ .opts = opts, .positionals = try positionals.toOwnedSlice(allocator) };
}

fn resolveToken(opts: GlobalOptions, allocator: std.mem.Allocator) !ResolvedToken {
    if (opts.token) |token| {
        return .{ .value = token, .owned = false };
    }

    const token = std.process.getEnvVarOwned(allocator, "CODA_API_TOKEN") catch return CliError.MissingToken;
    return .{ .value = token, .owned = true };
}

fn helpTarget(positionals: []const []const u8) ?HelpSelection {
    if (positionals.len == 0) return null;
    if (isHelpToken(positionals[0])) return .{ .resource = null, .action = null };
    if (positionals.len >= 2 and isHelpToken(positionals[1])) return .{ .resource = positionals[0], .action = null };

    var i: usize = 2;
    while (i < positionals.len) : (i += 1) {
        if (isHelpToken(positionals[i])) {
            return .{ .resource = positionals[0], .action = if (positionals.len >= 2) positionals[1] else null };
        }
    }

    return null;
}

fn printHelp(target: HelpSelection) void {
    if (target.resource == null) {
        printUsageStdout();
        return;
    }

    const resource = target.resource.?;
    if (std.mem.eql(u8, resource, "docs")) {
        if (target.action) |action| {
            if (std.mem.eql(u8, action, "list")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] docs list\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "get")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] docs get --doc <docId>\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "create")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] docs create (--payload <json> | --file <path>)\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "update")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] docs update --doc <docId> (--payload <json> | --file <path>)\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "delete")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] docs delete --doc <docId>\n", .{});
                return;
            }
        }
        printStdout("{s}", .{HELP_DOCS_TEXT});
        return;
    }

    if (std.mem.eql(u8, resource, "rows")) {
        if (target.action) |action| {
            if (std.mem.eql(u8, action, "list")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] rows list --doc <docId> --table <tableIdOrName> [--query <query>] [--limit <n>]\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "upsert")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] rows upsert --doc <docId> --table <tableIdOrName> (--payload <json> | --file <path>)\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "update")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] rows update --doc <docId> --table <tableIdOrName> --row <rowIdOrName> (--payload <json> | --file <path>)\n", .{});
                return;
            }
            if (std.mem.eql(u8, action, "delete-many")) {
                printStdout("Usage:\n  coda [--token <token>] [--json] rows delete-many --doc <docId> --table <tableIdOrName> (--payload <json> | --file <path>)\n", .{});
                return;
            }
        }
        printStdout("{s}", .{HELP_ROWS_TEXT});
        return;
    }

    printUsageStdout();
}

fn isHelpToken(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h");
}

fn requireFlag(args: []const []const u8, flag: []const u8, start: usize) ![]const u8 {
    const value = try optionalFlag(args, flag, start);
    if (value) |v| return v;
    printStderr("Missing required flag: {s}\n", .{flag});
    return CliError.MissingFlag;
}

fn requireFlagAny(args: []const []const u8, flags: []const []const u8, start: usize) ![]const u8 {
    const value = try optionalFlagAny(args, flags, start);
    if (value) |v| return v;
    printStderr("Missing required flag: {s}\n", .{flags[0]});
    return CliError.MissingFlag;
}

fn optionalFlag(args: []const []const u8, flag: []const u8, start: usize) !?[]const u8 {
    var i = start;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) {
            if (i + 1 >= args.len or isFlagLike(args[i + 1])) {
                printStderr("Missing value for {s}.\n", .{flag});
                return CliError.MissingValue;
            }
            return args[i + 1];
        }
    }
    return null;
}

fn optionalFlagAny(args: []const []const u8, flags: []const []const u8, start: usize) !?[]const u8 {
    var value: ?[]const u8 = null;
    for (flags) |flag| {
        const candidate = try optionalFlag(args, flag, start);
        if (candidate == null) continue;
        if (value) |existing| {
            if (!std.mem.eql(u8, existing, candidate.?)) {
                printStderr("Conflicting values for equivalent flags ({s}).\n", .{flags[0]});
                return CliError.Usage;
            }
            continue;
        }
        value = candidate;
    }
    return value;
}

fn ensureSupportedFlags(args: []const []const u8, start: usize, allowed_flags: []const []const u8) !void {
    var i = start;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!isFlagLike(arg)) {
            printStderr("Unexpected argument: {s}\n", .{arg});
            return CliError.Usage;
        }
        var allowed = false;
        for (allowed_flags) |flag| {
            if (std.mem.eql(u8, arg, flag)) {
                allowed = true;
                break;
            }
        }
        if (!allowed) {
            printStderr("Unsupported flag for this command: {s}\n", .{arg});
            return CliError.Usage;
        }

        if (i + 1 >= args.len or isFlagLike(args[i + 1])) {
            printStderr("Missing value for {s}.\n", .{arg});
            return CliError.MissingValue;
        }
        i += 1;
    }
}

fn isFlagLike(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "--");
}

fn jsonString(v: std.json.Value, key: []const u8) ?[]const u8 {
    if (v != .object) return null;
    if (v.object.get(key)) |inner| {
        return switch (inner) {
            .string => inner.string,
            else => null,
        };
    }
    return null;
}

fn printUsageStdout() void {
    printStdout("{s}", .{USAGE_TEXT});
}

fn printUsageStderr() void {
    printStderr("{s}", .{USAGE_TEXT});
}

fn printStdout(comptime format: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    defer writer.interface.flush() catch {};
    writer.interface.print(format, args) catch {};
}

fn printStderr(comptime format: []const u8, args: anytype) void {
    if (builtin.is_test) return;
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);
    defer writer.interface.flush() catch {};
    writer.interface.print(format, args) catch {};
}

test "parseCommandLine parses global flags and positionals" {
    const args = [_][]const u8{ "coda", "--json", "--token", "abc", "docs", "list" };
    const parsed = try parseCommandLine(std.testing.allocator, &args);
    defer std.testing.allocator.free(parsed.positionals);
    try std.testing.expect(parsed.opts.json);
    try std.testing.expectEqualStrings("abc", parsed.opts.token.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.positionals.len);
    try std.testing.expectEqualStrings("docs", parsed.positionals[0]);
}

test "parseCommandLine allows global flags after action" {
    const args = [_][]const u8{ "coda", "docs", "list", "-j", "--token", "abc" };
    const parsed = try parseCommandLine(std.testing.allocator, &args);
    defer std.testing.allocator.free(parsed.positionals);
    try std.testing.expect(parsed.opts.json);
    try std.testing.expectEqualStrings("abc", parsed.opts.token.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.positionals.len);
}

test "optionalFlag returns null when absent" {
    const args = [_][]const u8{ "coda", "rows", "list", "--doc", "d" };
    const value = try optionalFlag(&args, "--table", 1);
    try std.testing.expect(value == null);
}

test "optionalFlag errors on missing value" {
    const args = [_][]const u8{ "coda", "rows", "list", "--table" };
    try std.testing.expectError(CliError.MissingValue, optionalFlag(&args, "--table", 1));
}

test "helpTarget routes resource and action help" {
    const resource_help = [_][]const u8{ "rows", "--help" };
    const resource_target = helpTarget(&resource_help).?;
    try std.testing.expectEqualStrings("rows", resource_target.resource.?);
    try std.testing.expect(resource_target.action == null);

    const action_help = [_][]const u8{ "rows", "list", "--help" };
    const action_target = helpTarget(&action_help).?;
    try std.testing.expectEqualStrings("rows", action_target.resource.?);
    try std.testing.expectEqualStrings("list", action_target.action.?);
}

test "ensureSupportedFlags rejects unsupported flag" {
    const args = [_][]const u8{ "rows", "list", "--doc", "d", "--bogus", "x" };
    try std.testing.expectError(CliError.Usage, ensureSupportedFlags(&args, 2, &.{ "--doc", "--table" }));
}

test "optionalFlagAny detects conflicting alias values" {
    const args = [_][]const u8{ "rows", "list", "--doc", "d1", "--doc-id", "d2" };
    try std.testing.expectError(CliError.Usage, optionalFlagAny(&args, &.{ "--doc", "--doc-id" }, 2));
}

test "parseBoolean accepts true and false" {
    try std.testing.expect(try parseBoolean("true", "--flag"));
    try std.testing.expect(!(try parseBoolean("false", "--flag")));
}

test "parseBoolean rejects invalid values" {
    try std.testing.expectError(CliError.InvalidBoolean, parseBoolean("yes", "--flag"));
}

test "optionalFlagAny allows matching alias values" {
    const args = [_][]const u8{ "rows", "list", "--doc", "d1", "--doc-id", "d1" };
    const value = try optionalFlagAny(&args, &.{ "--doc", "--doc-id" }, 2);
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("d1", value.?);
}
