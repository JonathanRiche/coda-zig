const std = @import("std");

const BASE_URL = "https://coda.io/apis/v1";

const USAGE_TEXT =
    "Usage:\n" ++
    "  coda [--token <token>] [--json] docs list\n" ++
    "  coda [--token <token>] [--json] tables list --doc <docId>\n" ++
    "  coda [--token <token>] [--json] views list --doc <docId>\n" ++
    "  coda [--token <token>] [--json] rows list --doc <docId> --table <tableIdOrName> [--query <query>] [--limit <n>]\n" ++
    "  coda --help\n" ++
    "  coda -h\n" ++
    "\n" ++
    "Env:\n" ++
    "  CODA_API_TOKEN  Coda API token (used if --token is not provided)\n";

const CliError = error{
    Usage,
    MissingToken,
    MissingValue,
    HttpError,
    InvalidResponse,
};

const GlobalOptions = struct {
    token: ?[]const u8 = null,
    json: bool = false,
};

const ResolvedToken = struct {
    value: []const u8,
    owned: bool,

    fn deinit(self: ResolvedToken, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.value);
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

    if (args.len == 1 or hasHelpFlag(args)) {
        printUsageStdout();
        return 0;
    }

    const parsed = try parseGlobalOptions(args);
    var i: usize = parsed.next_index;

    if (i >= args.len) {
        return CliError.Usage;
    }

    const resource = args[i];
    i += 1;
    if (i >= args.len) return CliError.Usage;
    const action = args[i];
    i += 1;

    if (std.mem.eql(u8, resource, "docs") and std.mem.eql(u8, action, "list")) {
        const token = try resolveToken(parsed.opts, allocator);
        defer token.deinit(allocator);
        try listDocs(allocator, token.value, parsed.opts.json);
        return 0;
    }

    if (std.mem.eql(u8, resource, "tables") and std.mem.eql(u8, action, "list")) {
        const token = try resolveToken(parsed.opts, allocator);
        defer token.deinit(allocator);
        const doc = try requireFlag(args, "--doc", i);
        try listTables(allocator, token.value, doc, parsed.opts.json);
        return 0;
    }

    if (std.mem.eql(u8, resource, "views") and std.mem.eql(u8, action, "list")) {
        const token = try resolveToken(parsed.opts, allocator);
        defer token.deinit(allocator);
        const doc = try requireFlag(args, "--doc", i);
        try listViews(allocator, token.value, doc, parsed.opts.json);
        return 0;
    }

    if (std.mem.eql(u8, resource, "rows") and std.mem.eql(u8, action, "list")) {
        const token = try resolveToken(parsed.opts, allocator);
        defer token.deinit(allocator);
        const doc = try requireFlag(args, "--doc", i);
        const table = try requireFlag(args, "--table", i);
        const query = findFlag(args, "--query", i);
        const limit = findFlag(args, "--limit", i);
        try listRows(allocator, token.value, doc, table, query, limit, parsed.opts.json);
        return 0;
    }

    return CliError.Usage;
}

fn handleCliError(err: anyerror) u8 {
    switch (err) {
        CliError.Usage => {
            printError("Invalid command or arguments.");
            printUsageStderr();
            return 2;
        },
        CliError.MissingValue => {
            printError("Missing required flag value.");
            printUsageStderr();
            return 2;
        },
        CliError.MissingToken => {
            printError("Missing API token. Set CODA_API_TOKEN or pass --token <token>.");
            return 2;
        },
        CliError.HttpError => {
            printError("HTTP request failed. Check token permissions and provided IDs.");
            return 1;
        },
        CliError.InvalidResponse => {
            printError("Received an invalid response from Coda API.");
            return 1;
        },
        else => {
            var buf: [4096]u8 = undefined;
            var writer = std.fs.File.stderr().writer(&buf);
            defer writer.interface.flush() catch {};
            writer.interface.print("Unexpected error: {s}\n", .{@errorName(err)}) catch {};
            return 1;
        },
    }
}

fn hasHelpFlag(args: []const []const u8) bool {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            return true;
        }
    }
    return false;
}

fn printError(message: []const u8) void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);
    defer writer.interface.flush() catch {};
    writer.interface.print("{s}\n", .{message}) catch {};
}

fn printUsageStdout() void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buf);
    defer writer.interface.flush() catch {};
    writer.interface.print("{s}", .{USAGE_TEXT}) catch {};
}

fn printUsageStderr() void {
    var buf: [4096]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);
    defer writer.interface.flush() catch {};
    writer.interface.print("{s}", .{USAGE_TEXT}) catch {};
}

fn parseGlobalOptions(args: []const []const u8) !struct { opts: GlobalOptions, next_index: usize } {
    var opts = GlobalOptions{};
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            opts.json = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--token")) {
            if (i + 1 >= args.len) return CliError.MissingValue;
            opts.token = args[i + 1];
            i += 1;
            continue;
        }
        break;
    }

    return .{ .opts = opts, .next_index = i };
}

fn resolveToken(opts: GlobalOptions, allocator: std.mem.Allocator) !ResolvedToken {
    if (opts.token) |t| {
        return .{ .value = t, .owned = false };
    }

    const token = std.process.getEnvVarOwned(allocator, "CODA_API_TOKEN") catch return CliError.MissingToken;
    return .{ .value = token, .owned = true };
}

fn listDocs(allocator: std.mem.Allocator, token: []const u8, json_mode: bool) !void {
    var data = try fetchPaginated(allocator, token, BASE_URL ++ "/docs");
    defer data.deinit();
    try renderItems(data.items.items, json_mode, .docs);
}

fn listTables(allocator: std.mem.Allocator, token: []const u8, doc: []const u8, json_mode: bool) !void {
    const url = try std.fmt.allocPrint(allocator, BASE_URL ++ "/docs/{s}/tables", .{doc});
    defer allocator.free(url);
    var data = try fetchPaginated(allocator, token, url);
    defer data.deinit();
    try renderItems(data.items.items, json_mode, .tables);
}

fn listViews(allocator: std.mem.Allocator, token: []const u8, doc: []const u8, json_mode: bool) !void {
    const url = try std.fmt.allocPrint(allocator, BASE_URL ++ "/docs/{s}/views", .{doc});
    defer allocator.free(url);
    var data = try fetchPaginated(allocator, token, url);
    defer data.deinit();
    try renderItems(data.items.items, json_mode, .views);
}

fn listRows(allocator: std.mem.Allocator, token: []const u8, doc: []const u8, table: []const u8, query: ?[]const u8, limit: ?[]const u8, json_mode: bool) !void {
    var query_parts = std.ArrayList(u8){};
    defer query_parts.deinit(allocator);

    if (query) |q| {
        if (query_parts.items.len > 0) try query_parts.appendSlice(allocator, "&");
        try query_parts.writer(allocator).print("query={s}", .{q});
    }
    if (limit) |l| {
        if (query_parts.items.len > 0) try query_parts.appendSlice(allocator, "&");
        try query_parts.writer(allocator).print("limit={s}", .{l});
    }

    const suffix = if (query_parts.items.len > 0) "?" else "";
    const url = try std.fmt.allocPrint(allocator, BASE_URL ++ "/docs/{s}/tables/{s}/rows{s}{s}", .{ doc, table, suffix, query_parts.items });
    defer allocator.free(url);

    var data = try fetchPaginated(allocator, token, url);
    defer data.deinit();
    try renderItems(data.items.items, json_mode, .rows);
}

const Kind = enum { docs, tables, rows, views };

fn renderItems(items: []std.json.Value, json_mode: bool, kind: Kind) !void {
    if (json_mode) {
        std.debug.print("{f}\n", .{std.json.fmt(items, .{ .whitespace = .indent_2 })});
        return;
    }

    for (items) |item| {
        switch (kind) {
            .docs, .tables, .views => {
                std.debug.print("- {s} ({s})\n", .{ jsonString(item, "name") orelse "(unnamed)", jsonString(item, "id") orelse "n/a" });
            },
            .rows => {
                const row_id = jsonString(item, "id") orelse "n/a";
                const name = jsonString(item, "name") orelse "";
                if (name.len > 0) {
                    std.debug.print("- {s}: {s}\n", .{ row_id, name });
                } else {
                    std.debug.print("- {s}\n", .{row_id});
                }
            },
        }
    }
}

fn jsonString(v: std.json.Value, key: []const u8) ?[]const u8 {
    if (v != .object) return null;
    if (v.object.get(key)) |s| {
        return switch (s) {
            .string => s.string,
            else => null,
        };
    }
    return null;
}

const PagedItems = struct {
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(std.json.Value),

    fn deinit(self: *PagedItems) void {
        self.items.deinit(self.arena.allocator());
        self.arena.deinit();
    }
};

fn fetchPaginated(allocator: std.mem.Allocator, token: []const u8, first_url: []const u8) !PagedItems {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    var all = std.ArrayList(std.json.Value){};
    errdefer all.deinit(a);

    var next_url = try a.dupe(u8, first_url);

    while (true) {
        const body = try httpGet(allocator, token, next_url);
        defer allocator.free(body);

        const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
        const root = parsed.value;

        if (root != .object) return CliError.InvalidResponse;

        if (root.object.get("items")) |items| {
            if (items == .array) {
                for (items.array.items) |it| {
                    try all.append(a, it);
                }
            }
        }

        if (root.object.get("nextPageLink")) |npl| {
            if (npl == .string and npl.string.len > 0) {
                next_url = try a.dupe(u8, npl.string);
                continue;
            }
        }
        break;
    }

    return .{ .arena = arena, .items = all };
}

fn httpGet(allocator: std.mem.Allocator, token: []const u8, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const auth = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
    defer allocator.free(auth);

    const headers = [_]std.http.Header{
        .{ .name = "authorization", .value = auth },
        .{ .name = "accept", .value = "application/json" },
    };

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .extra_headers = &headers,
        .response_writer = &aw.writer,
    });

    if (@intFromEnum(result.status) >= 400) {
        return CliError.HttpError;
    }

    return aw.toOwnedSlice();
}

fn requireFlag(args: []const []const u8, flag: []const u8, start: usize) ![]const u8 {
    return findFlag(args, flag, start) orelse CliError.MissingValue;
}

fn findFlag(args: []const []const u8, flag: []const u8, start: usize) ?[]const u8 {
    var i = start;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) {
            if (i + 1 < args.len) return args[i + 1];
            return null;
        }
    }
    return null;
}
