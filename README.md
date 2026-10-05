# snapshot

Mirrors a source tree to a destination with parallel rsync workers, and
optionally removes destination entries that are no longer in the source.

The source is authoritative: anything at the destination that the source
does not have is stale. Deletion is opt-in, via `--delete`.

## Build

```sh
mix escript.build     # produces ./snapshot
```

## Use

```sh
snapshot <src> <dst> [options]
```

Copy new and changed files. Nothing is ever deleted.

```sh
snapshot /Volumes/Current/Media ~/snapshot
```

Preview a sweep without removing anything — combine `--delete` with
`--dry-run` to see the exact list first.

```sh
snapshot /Volumes/Current/Media ~/snapshot --delete --dry-run
```

Then actually remove them.

```sh
snapshot /Volumes/Current/Media ~/snapshot --delete
```

| Option | |
|---|---|
| `-w, --workers N` | parallel rsync workers (default 11) |
| `--retries N` | retries per batch (default 2) |
| `-n, --dry-run` | pass `--dry-run` to rsync; with `--delete`, preview deletions |
| `--delete` | after a successful sync, remove destination files and directories no longer in the source. Off by default. |
| `--exclude PATTERN` | repeatable; defaults to `.DS_Store` |
| `--flags "..."` | extra raw rsync flags |
| `--rsync-path PATH` | explicit rsync binary (must be rsync 3.x) |

## Deleting safely

`--delete` never guesses. It asks rsync which destination paths are absent
from the source, in a recursive dry run, and removes exactly those. Three
consequences worth knowing:

- **`--exclude` applies.** A destination path matching an exclude pattern is
  never deleted.
- **An unreadable source stops everything.** If rsync cannot read part of the
  source it exits non-zero, and nothing is deleted. A source that contains no
  files at all is also refused — that is what an unmounted volume looks like,
  and rsync on its own would delete the entire destination for it.
- **Directories go too**, in the order rsync considers safe.

A directory renamed at the source is deleted and re-copied under its new
name. Nothing is renamed in place; that costs a full re-transfer of the
folder, and buys never having to decide that one destination folder holds
the same data as another.

## Tests

```sh
mix test
```

Requires a real rsync 3.x; macOS ships openrsync 2.6.9 at `/usr/bin/rsync`,
which this tool refuses. Tests that need it are skipped if none is found.