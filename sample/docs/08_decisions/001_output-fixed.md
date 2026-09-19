# 001: Fix the output to "Hello Claude!"

## Context

The purpose of the sample is to show the sprint flow itself. It is not to show a complex implementation.

## Decision

Fix the return value of `hello()` to `"Hello Claude!"`. It takes no input. Settings and the environment do not change it.

## Consequences

Clause [HELLO-1](../05_specifications/hello.md#HELLO-1), the implementation, and the test always agree. To make the message variable in the future, write a new ADR that supersedes this decision.
