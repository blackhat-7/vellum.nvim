# Orbit

[![build](https://img.shields.io/badge/build-passing-2ea44f.svg)](#) [![version](https://img.shields.io/badge/version-2.4.0-8957e5.svg)](#) [![license](https://img.shields.io/badge/license-MIT-blue.svg)](#)

A **tiny job queue** for Lua services. Jobs survive restarts, retry with
backoff, and never run twice. Read the [guide](#) or jump to `orbit.push()`.

> [!TIP]
> Orbit needs no broker. A single SQLite file holds every queue.

## How a job flows

```mermaid
flowchart LR
  P[Producer] -->|push| Q[(Queue)]
  Q -->|lease| W1[Worker]
  Q -->|lease| W2[Worker]
  W1 -->|ack| D[Done]
  W2 -.->|fail| R[Retry with backoff]
  R --> Q
```

## Why Orbit

| Feature        | Orbit | Redis queue | Cron |
| :------------- | :---: | :---------: | :--: |
| Exactly once   |   ✓   |      ✗      |  ✗   |
| No extra server|   ✓   |      ✗      |  ✓   |
| Retries        |   ✓   |      ✓      |  ✗   |

## Quick start

```lua
local orbit = require('orbit')
local q = orbit.open('jobs.db')

q:push('email', { to = 'ada@example.com' })
q:work('email', function(job)
  send(job.to) -- throws → retried later
end)
```

## Backoff

Retry $n$ waits $d_0 \cdot 2^n$ seconds, capped at an hour:

$$
d_n = \min\left(3600,\; d_0 \cdot 2^{n}\right)
$$

## Roadmap

- [x] Durable queues on SQLite
- [x] Retries with exponential backoff
- [ ] Priorities
- [ ] Web dashboard

> [!WARNING]
> Workers must be **idempotent**: a crash after the side effect but before
> the ack runs the job again.

## A job's life

```mermaid
sequenceDiagram
  participant App
  participant Orbit
  participant Worker
  App->>Orbit: push(job)
  Orbit-->>App: id
  Worker->>Orbit: lease()
  Orbit-->>Worker: job
  Worker->>Orbit: ack(id)
```

<details>
<summary>Why SQLite and not Postgres?</summary>

One file, zero setup, and `BEGIN IMMEDIATE` gives the locking Orbit needs.
Postgres support is planned[^1].

</details>

---

Made with care. Released under the MIT license.

[^1]: Behind the `orbit.pg` flag in 3.0.
