# 0074 - Fix 404 on Label Refresh by Introducing Explicit `labelId` in Web Routing

Date: 2026-03-18

## Status

Proposed

## Context

Refreshing a label view on web results in a 404 error because label IDs are incorrectly interpreted as `mailboxId` from the URL.

## Decision

Introduce an explicit `labelId` query parameter to distinguish labels from mailboxes in routing.

* Mailbox: `/dashboard?context=<mailboxId>`
* Label: `/dashboard?labelId=<labelId>`

## Consequences

* ✅ Fixes 404 on refresh
* ✅ Enables correct deep linking and bookmarking
* ⚠️ Requires updating routing logic and URL generation
* ⚠️ Legacy URLs must be handled via fallback logic