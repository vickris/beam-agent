---
name: otp-review
description: "Use when reviewing BeamAgent Elixir/OTP changes for GenServer correctness, supervision, process isolation, concurrency, timeouts, message handling, or fault recovery."
---

# Review OTP Changes

## Review procedure

Inspect:

1. process ownership
2. supervision
3. restart semantics
4. message ordering
5. timeouts
6. process leaks
7. GenServer bottlenecks
8. DynamicSupervisor usage
9. Registry usage
10. Distributed-node assumptions

## Report findings

Prioritize concrete bugs by severity. For each, cite the affected module/function and describe a reproducible consequence. Separate confirmed findings from risks or questions. If no actionable issue is found, say so and note the checks performed; do not infer correctness solely from compilation.
