# Generic software review profile

Prioritize by blast radius: spend effort on failures that are expensive, dangerous, or hard to
detect first. Actively probe these high-cost classes. This checklist primes the search; it is not a
limit:

- auth, permissions, tenant isolation, trust boundaries
- data loss, corruption, duplication, and irreversible state changes
- rollback safety, retries, partial failure, and idempotency gaps
- race conditions, ordering assumptions, stale state, and re-entrancy
- empty-state, null, timeout, and degraded-dependency behavior
- version skew, schema drift, migration hazards, and compatibility regressions
- observability gaps that would hide a failure or slow recovery
