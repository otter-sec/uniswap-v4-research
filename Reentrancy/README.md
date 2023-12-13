# Vulnerability Pattern 2 - Reentrancy

## Issue

One long standing issue in solidity is reentrancy, and hooks are no exception. UniswapV4 itself is written in a way to ensure that reentrancy wouldn't affect it's internal states, but the same is not guaranteed for hooks. Since uniswapv4 does not adopt reentrancy guards, hook contracts must make their own decision on whether reentrancy is impactful to their business logic, and if the answer is yes, how to prevent it.

A minimal example of this is [vuln.sol](), where the donate bonus can be claimed several times by reentering `afterDonate` function.

## Mitigation

As usual, there are no catch-call protections for reentrancy bugs, but a few rules can be followed to minimize the risk.

1. Eliminate external calls if possible. Without outbounding contract calls, the execution flow will never be handed back to user and reentrancy won't be possible
2. Use reentrancy guards. If external calls are necessary, consider adding reentrancy guards on functions that are not explicitly meant to be reentrant.
3. Conform to the check effect interaction pattern. If reentrancy guard is not desired, whether for gas saving or other reasons, the check effect interaction pattern may also help ensure that reentrancies won't lead to unexpected check bypasses. However, also note that this requires a bit more effort to get correct compared to the other two options listed above.

## In the wild examples
https://github.com/mrhouzlane/CaptainHooks/blob/main/packages/foundry/contracts/UniversalHook.sol#L407
