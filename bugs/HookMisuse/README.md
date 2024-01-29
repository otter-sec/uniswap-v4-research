# Vulnerability Pattern 4 - Hook Misuse

## Issue

Flexibility almost always comes at the cost of complexity. Pool deployers are now expected to understand the internals of Uniswap v4 before being able to expand the functionalities with hooks.

One of the most straightforward vulnerabilities developers may create is misunderstanding the use of hooks. For instance, in the example [VulnHook.sol](./VulnHook.sol), the code incorrectly assumes it is responsible for calling `poolManager.swap` after passing a check. Due to the locking mechanism in Uniswap v4, the call will always revert, rendering the pool unswappable.

While this bug seems obvious, in more complex codebases, such mistakes may not be as easy to spot and could easily escape the developer's attention. Observe how often on-chain oracle/pricefeed APIs are misused, and it should be obvious that mistakes are bound to be made at some point.

Other potential hook misuses could include misunderstanding when hooks are called. For instance, I challenge readers to explain what the recently added NoOp hook is used for without checking the source code. With more hooks to be added before the Uniswap v4 launch, the complexity only grows, and developers must keep up with the latest codebase to prevent misuse of those hooks.

## Mitigation

Aside from reading univ4 documents and code, another way to prevent those coding mistakes is to write integration tests rigorously. With high test coverage, API misuse should be easy to spot since even the simplest input usually yields highly different execution results (as opposed to security bugs, which might require complex inputs to trigger).



