# 0072 - Thread-aware bulk actions for EmailList with collapseThreads using expansion and dedicated Interactors

Date: 2026-03-17

## Status

Proposed

## Context

After enabling `collapseThreads = true` (ADR-0071), each item in the `EmailList` represents a **ThreadId** instead of an individual `EmailId`.

### Preconditions (from ADR-0071)

Thread-aware flow is enabled only when:
1. Session capability indicates `collapseThreads` is supported.
2. User Settings toggle for thread mode is enabled.

If either condition is false, keep existing EmailId-based flow.

However, the current system:

* All actions (`markAsRead`, `move`, `star`, etc.) operate on:

```dart
List<EmailId>
```

* Existing interactors:

    * `MarkAsEmailReadInteractor` (single email)
    * `MarkAsMultipleEmailReadInteractor` (bulk email)

* Existing repository:

```dart
abstract class ThreadDetailRepository {
  Future<List<EmailInThreadDetailInfo>> getThreadById(
    ThreadId threadId,
    Session session,
    AccountId accountId,
    MailboxId sentMailboxId,
    String ownEmailAddress,
  );
}
```

## Problem

When users perform actions on:

* a single thread
* multiple threads (multi-select)
* or a mix of threads and emails

the system must resolve:

```text
ThreadId → List<EmailInThreadDetailInfo>
```

Key challenges:

* N+1 API calls (`getThreadById`)
* Partial failures (one thread fails while others succeed)
* Duplicate `EmailInThreadDetailInfo`s when merging results
* High latency with large selections
* Existing interactors are not designed for thread-level inputs

## Decision

### Adopt:

> **Thread-aware Interactors + Thread Expansion Service (cached, parallel, error-isolated) + reuse existing Email Interactors**

## Architecture Overview

```text
User Action (UI)
    ↓
Thread-aware Interactor (Stream<UIState>)
    ↓
ThreadExpansionService
    ↓
List<EmailInThreadDetailInfo> (deduplicated & pagination-safe)
    ↓
Existing Email Interactor (Stream)
    ↓
UI State Update (Optimistic + Server Sync)
```

## 1. Thread Expansion Service

### Responsibility

* Convert `List<ThreadId>` → `List<EmailInThreadDetailInfo>`
* Reuse `ThreadDetailRepository.getThreadById`
* Handle:

    * caching
    * parallel execution
    * error isolation
    * pagination awareness

### Pagination Awareness

We've already handled pagination for the `Email/set` and `Email/get` methods 
in the mixins `BatchSetEmailProcessingMixin` and `BatchGetEmailProcessingMixin`, 
so we just need to call and use them.

### Data Model

```dart
class ThreadExpansionResult {
  final List<EmailInThreadDetailInfo> emailThreadInfos;
  final Map<ThreadId, Object> errors;

  ThreadExpansionResult({
    required this.emailThreadInfos,
    required this.errors,
  });
}
```

### Implementation

```dart
class ThreadExpansionService {
  final ThreadDetailRepository threadDetailRepository;

  final Map<ThreadId, List<EmailInThreadDetailInfo>> _cache = {};

  ThreadExpansionService(this.threadDetailRepository);

  Future<ThreadExpansionResult> expandThreads({
    required List<ThreadId> threadIds,
    required Session session,
    required AccountId accountId,
    required MailboxId sentMailboxId,
    required String ownEmailAddress,
  }) async {
    final emailThreadInfos = <EmailInThreadDetailInfo>{};
    final errors = <ThreadId, Object>{};

    final futures = threadIds.map((threadId) async {
      try {
        // Cache hit
        if (_cache.containsKey(threadId)) {
          emailIds.addAll(_cache[threadId]!);
          return;
        }

        final threadDetails = await threadDetailRepository.getThreadById(
          threadId,
          session,
          accountId,
          sentMailboxId,
          ownEmailAddress,
        );

        _cache[threadId] = threadDetails;
        emailIds.addAll(threadDetails);
      } catch (e) {
        // Error isolation
        errors[threadId] = e;
      }
    });

    await Future.wait(futures);

    return ThreadExpansionResult(
      emailThreadInfos: emailThreadInfos.toList(),
      errors: errors,
    );
  }

  void clearCache() => _cache.clear();
}
```

## 2. Thread-aware Interactor Pattern

### Principles

* Do not modify existing email interactors
* Do not duplicate business logic
* Only:

    * expand threads
    * delegate to existing email interactors

### Result Model

```dart
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/error/set_error.dart';

class ThreadActionResult {
  final List<EmailInThreadDetailInfo> success;
  final Map<Id, SetError> actionErrors;
  final Map<ThreadId, Object> expansionErrors;

  ThreadActionResult({
    required this.success,
    required this.actionErrors,
    required this.expansionErrors,
  });
}
```

## 3. Example Implementations

### 3.1 MarkAsThreadReadInteractor

```dart
class MarkAsThreadReadInteractor {
  final ThreadExpansionService expansionService;
  final EmailRepository emailRepository;

  MarkAsThreadReadInteractor(
    this.expansionService,
    this.emailRepository,
  );

  Stream<Either<Failure, Success>> execute({
    required Session session,
    required AccountId accountId,
    required MailboxId sentMailboxId,
    required String ownEmailAddress,
    required ReadActions readAction,
    List<ThreadId> threadIds = const [],
    List<EmailInThreadDetailInfo> emailThreadInfos = const [],
  }) async* {
    yield Right(LoadingMarkAsThreadRead());
    
    final expansion = await expansionService.expandThreads(
      threadIds: threadIds,
      session: session,
      accountId: accountId,
      sentMailboxId: sentMailboxId,
      ownEmailAddress: ownEmailAddress,
    );

    final allEmailThreadInfos = {
      ...emailThreadInfos,
      ...expansion.emailThreadInfos,
    }.toList();

    if (allEmailThreadInfos.isEmpty) {
      yield Left(MarkAsThreadReadFailure(ThreadActionResult(
        success: [],
        actionErrors: {},
        expansionErrors: expansion.errors,
      )));
      return;
    }

    final result = await emailRepository.markAsRead(
      session,
      accountId,
      allEmailThreadInfos.emailIds,
      readAction,
    );

    yield Right(MarkAsThreadReadSuccess(ThreadActionResult(
      success: result.emailIdsSuccess,
      actionErrors: result.mapErrors,
      expansionErrors: expansion.errors,
    )));
  }
}
```

### 3.2 MoveThreadInteractor

```dart
class MoveThreadInteractor {
  final ThreadExpansionService expansionService;
  final EmailRepository emailRepository;

  MoveThreadInteractor(
    this.expansionService,
    this.emailRepository,
  );

  Stream<Either<Failure, Success>> execute({
    required Session session,
    required AccountId accountId,
    required MailboxId sentMailboxId,
    required String ownEmailAddress,
    required MailboxId destinationMailboxId,
    List<ThreadId> threadIds = const [],
    List<EmailInThreadDetailInfo> emailThreadInfos = const [],
  }) async* {
    yield Right(LoadingMoveThread());
    
    final expansion = await expansionService.expandThreads(
      threadIds: threadIds,
      session: session,
      accountId: accountId,
      sentMailboxId: sentMailboxId,
      ownEmailAddress: ownEmailAddress,
    );

    final allEmailThreadInfos = {
      ...emailThreadInfos,
      ...expansion.emailThreadInfos,
    }.toList();
    
     if (allEmailThreadInfos.isEmpty) {
       yield Left(MarkAsThreadReadFailure(ThreadActionResult(
         success: [],
         actionErrors: {},
         expansionErrors: expansion.errors,
       )));
       return;
    }

    final moveRequest = MoveToMailboxRequest.fromThreadInfos(threadInfos: allEmailThreadInfos);
     
    final result = await emailRepository.moveToMailbox(session, accountId, moveRequest);

    yield Right(MarkAsThreadReadSuccess(ThreadActionResult(
      success: result.emailIdsSuccess,
      actionErrors: result.mapErrors,
      expansionErrors: expansion.errors,
    )));
  }
}
```

## 3. UI Responsiveness

### Problem

Delay between:

```text
User action → Interactor → Server → UI update
```

causes:

* Perceived lag
* Poor UX in bulk/thread actions

### Decision: Optimistic UI Update

Immediately update UI before server response.

### Flow

```text
User click "Mark as read"
    ↓
UI updates instantly (optimistic)
    ↓
Interactor executes
    ↓
Server response:
    - success → keep state
    - partial → reconcile
    - failure → rollback
```

### UI State Strategy

| Case    | Behavior           |
| ------- | ------------------ |
| Loading | Already updated UI |
| Success | Confirm            |
| Partial | Patch missing      |
| Failure | Rollback           |

### Per Email UI Update

Even when acting on thread:

👉 UI updates must happen at **Email level**, not Thread only.

Reason:

* Thread UI derived from Email states
* Avoid inconsistent UI

## Implementation Strategy

Instead of maintaining a separate snapshot system, we **reuse existing domain logic**:

```dart
updateEmailFlagByEmailIds(...)
```

### Key Principle

> UI is updated by mutating `PresentationEmail.keywords` immediately

## Optimistic Update Flow

```text
User click (mark read/star)
    ↓
MailboxDashboardController.updateEmailFlagByEmailIds(...)   ← (optimistic)
    ↓
UI updates instantly (via RxList.refresh)
    ↓
Interactor.execute() (async)
    ↓
Server response:
    - success → do nothing
    - partial → reconcile (optional)
    - failure → rollback (via reverse update)
```

## Controller-Level Implementation

### ✅ Optimistic Update Trigger

```dart
controller.updateEmailFlagByEmailIds(
  emailIds,
  readAction: ReadActions.markAsRead,
);
```

OR

```dart
controller.updateEmailFlagByEmailIds(
  emailIds,
  markStarAction: MarkStarAction.markStar,
);
```

## 🔁 Rollback Strategy

Instead of snapshot map, rollback is performed by **inverse operation**:

| Action     | Rollback     |
| ---------- | ------------ |
| markAsRead | markAsUnread |
| markStar   | unMarkStar   |

### Example

```dart
controller.updateEmailFlagByEmailIds(
  emailIds,
  readAction: ReadActions.markAsUnread, // rollback
);
```

## ⚠️ Partial Success Handling

When:

```text
Some emailIds succeed, some fail
```

We perform:

```dart
final failedIds = allIds - successIds;

controller.updateEmailFlagByEmailIds(
  failedIds,
  readAction: ReadActions.markAsUnread,
);
```

## 🔄 Keyword-based Update Model

### Core Mechanism

```dart
presentationEmail.keywords?[keyword] = true;
presentationEmail.keywords?.remove(keyword);
```

This ensures:

* Fine-grained update (no full object replace)
* No unnecessary rebuilds
* Compatible with JMAP keyword model

## 📡 UI Sync Behavior

### Why this works well

Because:

```dart
currentEmails.refresh();
```

ensures:

* Immediate UI re-render
* Works for both:

  * mailbox list
  * search result list

## 🔗 Thread Detail Synchronization

When updating single email:

```dart
dispatchThreadDetailUIAction(UpdatedEmailKeywordsAction(...));
```

ensures:

* Thread detail UI stays consistent
* Avoids mismatch between:

  * EmailList
  * ThreadDetail screen

## ⚠️ Limitations

### 1. No Snapshot → No True Rollback

Trade-off:

* ✅ Simpler implementation
* ❌ Cannot restore original complex state (only inverse action)

### 2. Concurrent Actions Risk

Example:

```text
Action A: mark as read
Action B: mark as unread (before A completes)
```

👉 May cause inconsistency

### 3. WebSocket Override

If WebSocket pushes state:

* It may override optimistic state
* This is acceptable (server is source of truth)

## 5. Key Design Properties

### Error Isolation

* Each thread expansion is wrapped in `try/catch`
* Failure of one thread does not affect others

### Deduplication

```dart

final allEmailThreadInfos = {
  ...emailThreadInfos,
  ...expandedEmailThreadInfos,
};
```

### Cache

```dart
Map<ThreadId, List<EmailInThreadDetailInfo>>
```

* Reduces repeated calls to `getThreadById`
* Improves performance for repeated actions

### Parallel Execution

```dart
await Future.wait(...);
```

* Minimizes latency for multi-thread operations

## 6. Cache Invalidation

Cache must be cleared when:

* Mailbox sync occurs
* Thread content changes
* Websocket event (Refresh change invoke )
* `collapseThreads` is toggled

```dart
expansionService.clearCache();
```

### Implementation Points

Hook `expansionService.clearCache()` in:

- `ThreadController.refreshAllEmail()` after mailbox sync completes (see lib/features/thread/presentation/thread_controller.dart)
- `ThreadController.refreshChangeEmail()` after calling `clearCache()` post-action
- Settings controller's `onCollapseThreadsToggled()` callback (or equivalent setter)
- Thread actions are performed

## Consequences

### Positive

* Reuses all existing email business logic
* No backend changes required
* Scales well for multi-selection
* Supports partial success (better UX)
* Clear separation between Thread and Email domains

### Negative

* Increased number of interactors
* Requires careful cache invalidation
* Still involves multiple API calls (mitigated via cache + parallelism)
* Stream-based integration adds complexity (async iteration, result collection, state management)
* Complex request object construction (MoveToMailboxRequest, emailIdsByMailboxId) requires additional context gathering

## Summary

```text
Thread Action Flow:

ThreadIds
  → expandThreads (parallel + cache + error-isolated)
  → extract EmailInThreadDetailInfo
  → deduplicate
  → call existing Email Interactor
  → return (success + actionErrors + expansionErrors)
```
