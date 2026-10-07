# Known Issues

## Tool effect classification

Tools currently have no read/write or side-effect classification.

Future work should introduce an explicit effect model or policy hook before
tool execution.

## Tool-call context compression

Context compression operates on individual messages and can separate a tool
request from its corresponding tool result.

Compression should preserve logical tool exchanges.

## Failure-state preservation

Crash and timeout results currently lose accumulated trace and execution
counters.

Failure results should preserve available diagnostic state.

## API startup failure contract

Runner startup errors may not return the documented API result tuple.

## Tool call trace counter

`:tool_started` can record an incorrect tool-call sequence number.
