# CPU topology override & stale-thread recovery (ntdll + wineserver)

Two related reliability features live in Wine's core process layer: a
Proton-compatible **CPU topology override** so Live sees a sane, bounded CPU
layout, and **stale-thread recovery** so a crashed plug-in thread cannot wedge
the whole wineserver. Together they bump the wineserver protocol from 956 to
960.

## Part 1 — `WINE_CPU_TOPOLOGY`

### Problem

DAWs make scheduling decisions from the CPU topology Windows reports. On big
hybrid CPUs (P+E cores, high thread counts) Live behaves worse, and Linux
cpusets/affinity limits (containers, `taskset`) confuse code that assumes it
owns every CPU it can see. ENCORE wants to present a small, stable set of
(preferably performance) cores — the launcher caps it at **8 logical CPUs** via
`scripts/select-cpu-topology.sh`.

### Grammar

```
WINE_CPU_TOPOLOGY=<logical-cpu-count>
WINE_CPU_TOPOLOGY=<logical-cpu-count>:<host-cpu-id>,...
WINE_CPU_TOPOLOGY=<physical-core-count>s:<host-cpu-id>,...
```

The bare-count form lets Wine choose which host CPUs to use; the explicit forms
pin them. The `s` form reports two SMT siblings per physical core.

### How the mapping is built (`fill_cpu_override`, `dlls/ntdll/unix/system.c`)

- Queries the allowed CPU set with `sched_getaffinity` — the override composes
  with cpusets rather than fighting them. A count exceeding the allowed CPUs is
  ignored (with a trace), not an error.
- For the bare-count form it reads each CPU's
  `topology/thread_siblings_list` and selects CPUs in up to three passes:
  first **distinct physical P-cores only**, then P-cores allowing SMT siblings,
  then any allowed CPU — so `WINE_CPU_TOPOLOGY=8` on a hybrid part prefers
  8 real performance cores.
- Explicit lists are validated hard: every ID must be in the allowed set, in
  range, and unique. Invalid strings clear the override with an `ERR`.
- The result is a `struct cpu_topology_override`
  (`cpu_count`, `host_cpu_id[64]`, `core_id[64]`) plus per-virtual-CPU sibling
  masks.

### One authoritative mapping per process tree

`server_init_process()` (`dlls/ntdll/unix/server.c`) parses the environment
only in the first process, attaches the override as vararg data on
**`init_first_thread`**, and then always calls the new
**`get_cpu_topology_override`** server request, adopting whatever the server
returns. The server (`server/thread.c`) validates the submitted mapping
(size, bounds, `core_id < cpu_count`, no duplicate host IDs, consistency with
any existing mapping) and stores it on the process; children inherit it in
`create_process()`. Every process in the tree therefore agrees on the same
virtual→host mapping even if environments diverge.

### What Windows code sees

With an override active, ntdll remaps every topology surface:

- `peb->NumberOfProcessors` and `NtGetCurrentProcessorNumber` (host
  `sched_getcpu()` result translated to the virtual index; a thread that lands
  outside the mapping is reported as CPU 0 with a `WARN`).
- `NtQuerySystemInformation` logical-processor info: cores from the sibling
  masks, caches via a new `sysfs_map_cpu_list()` reading `shared_cpu_list`,
  NUMA via `cpulist`, hybrid `EfficiencyClass` looked up by **host** CPU ID.
- Idle times, TSC/base frequencies, and `NtPowerInformation` max/scaling
  frequencies — all read from the mapped host CPUs' sysfs nodes.
- Affinity: `set_thread_affinity` (`server/thread.c`) translates virtual
  affinity bits into `CPU_SET(host_cpu_id[i])` for `sched_setaffinity`;
  `get_thread_affinity` reverse-maps; `is_valid_process_affinity`
  (`server/process.h`) rejects affinity masks with bits above `cpu_count`, and
  `init_first_thread` pins the initial process to exactly the mapped set.

### Interaction with the launcher

`scripts/run-ableton.sh` sets `WINE_CPU_TOPOLOGY` from (in order)
`ENCORE_CPU_TOPOLOGY`, an existing `WINE_CPU_TOPOLOGY`, or
`scripts/select-cpu-topology.sh`, which inspects `Cpus_allowed_list` and emits:
`8` when more than eight CPUs are allowed; the supported count when the allowed
set is sparse or affinity-limited; nothing (no override) when the default dense
set is already ≤ 8. See [../environment.md](../environment.md).

## Part 2 — stale-thread recovery (`server/ptrace.c`, `server/thread.c`)

### Problem

When a Unix thread backing a Windows thread dies unexpectedly (plug-in crash,
OOM-kill), upstream Wine's ptrace layer just cleared `unix_pid`/`unix_tid`
wherever it happened to notice (`ESRCH`, `ECHILD`). The Windows-side thread
object stayed RUNNING forever: locks never released, waits never completed —
a wedged wineserver with Live still "running".

### What the patch does

- New `handle_unix_thread_exit(thread, reason)`: if the thread is still
  RUNNING, it grabs a reference and schedules
  `terminate_exited_unix_thread` via a **zero-delay timeout callback** — so
  `kill_thread()` runs outside whatever ptrace callback or list traversal
  detected the death (calling it inline could corrupt the caller's state).
  The exit code is set to `STATUS_UNSUCCESSFUL` unless one was already
  explicitly supplied, tracked by a new `thread->exit_code_set` flag
  (`server/thread.h`; set by `terminate_thread` and `terminate_process`).
  A clear one-line notice is printed:
  `Unix peer pid=… tid=… exited while its Windows thread remained running (…); retiring it`.
- New `unix_thread_is_dead()`: confirms ambiguous `ESRCH` results with a
  signal-0 liveness probe (`tkill`, falling back to `kill` on `ENOSYS`) before
  declaring death — `ESRCH` from ptrace alone can be a lie (e.g. attach races).
  Used by `send_thread_signal`, `resume_after_ptrace`, `suspend_for_ptrace`,
  and the `waitpid` `ECHILD` path.
- `sigchld_callback` on Linux looks the thread up **by tid only**
  (`waitpid` returns the exact traced task id), avoiding a wrong-thread match
  via the pid fallback.

### Caveats

- The zero-delay callback allocation is load-bearing; on OOM the server
  `fatal_error`s rather than leak a zombie RUNNING thread.
- `terminate_process` now records the exit code for every thread even when it
  is 0 (paired with `exit_code_set`), a subtle behavioural fix.

## Key files

| File | Role |
| --- | --- |
| `dlls/ntdll/unix/system.c` | `fill_cpu_override`, `adopt_cpu_override`, all topology remapping (+~420) |
| `dlls/ntdll/unix/server.c` | send override on `init_first_thread`; adopt authoritative mapping |
| `dlls/ntdll/unix/thread.c` | `NtGetCurrentProcessorNumber` remap |
| `server/protocol.def`, `include/wine/server_protocol.h` | `cpu_topology_override` struct, new request, protocol 956→960 |
| `server/thread.c` / `thread.h` | validation, affinity mapping, `exit_code_set`, request handler |
| `server/process.c` / `process.h` | inheritance, `is_valid_process_affinity` |
| `server/ptrace.c` | `handle_unix_thread_exit`, `unix_thread_is_dead` |
| `server/request_handlers.h`, `request_trace.h`, `trace.c` | request plumbing + trace dumper |

## How to verify

`WINE_CPU_TOPOLOGY=4 wine cmd /c "echo %NUMBER_OF_PROCESSORS%"` should print 4,
and `wine: overriding CPU configuration, 4 logical CPUs, host CPUs …` appears on
stderr. Task Manager-style tools inside the prefix should show the reduced
topology. For thread recovery, kill a Wine thread from the host
(`kill -KILL <tid>`) and confirm the server prints the retiring notice instead
of leaving the process wedged.
