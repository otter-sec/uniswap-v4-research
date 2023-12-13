# Vulnerability Pattern 4 - Hook Misuse

## Issue

Flexibility almost always comes at the cost of complexity. Pool deployers are now expected to understand the internals of uniswapv4 before being able to expand the functionalities with hooks.

One of the most straightforward bugs that could be made is misunderstanding of what hooks are used for. For instance, in the example [vuln.sol](), we can see that the code incorrectly assumed that it is responsible for calling `poolManager.swap` after passing a check. Due to the locking mechanism in uniswapv4, the call will always revert, rendering the pool unswappable.

While this bug seems dumb, we believe that in more complex codebases, such mistakes may not be as obvious, and could easily escape developer's attention. Just look at how often on-chain oracle / pricefeed apis are misused, and it should be obvious that mistakes are bound to be made at some point.

Other potential hook misuses could include misunderstanding of when hooks are called. For instance, I challenge readers to explain what the recently added NoOp hook is used for without checking the source code. With more hooks to be added before univ4 launch, the complexity only grows, and developers must keep up with the latest codebase to prevent misuse of those hooks.

## Mitigation

Aside from reading univ4 documents and code, another way to prevent those coding mistakes to write integration tests rigorously. With high test coverage, api misuse should be easy to spot, since even the simpliest input usually yields highly different execution results (as opposed to security bugs, which might require complex inputs to trigger).

## In the wild examples
https://github.com/Shivamycodee/WID-KYC-Hook/blob/master/src/WorldIDKyc.sol#L112
