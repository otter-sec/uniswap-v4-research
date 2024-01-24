# Vulnerability Pattern 1 - Lack Of Access Control

## Issue

Since hooks are used to handle supplementary logic for pools, there is a high chance that the hook contract must maintain its own state. Similarly, if any malicious parties are able to manipulate the storage within the contract, it may bring exploitable bugs.

A common source of contract mismanagement is a lack of access control. In the context of Uniswap v4 hooks, we have several external facing functions (hooks) that should only be called by the `PoolManager`. If any of those functions modify the hook contract state but do not limit its caller, attackers may directly call them, resulting in unexpected manipulation of the contract state.

We present a minimal example of this in [VulnHook.sol](./VulnHook.sol), where the `swapCnt` counter tracks total swaps performed on the `Pool`, but is manipulatable by users who directly call `beforeSwap` due to lack of access control.

## Mitigation

While this is the most widespread bug we found in public hook implementations (~50% didn't properly check caller), it is also easily fixable. In fact, [BaseHook.sol](https://github.com/Uniswap/v4-periphery/blob/886403181f707f9645d59d47180cca042bc4eb87/contracts/BaseHook.sol) provided by uniswap already contains a `poolManagerOnly` modifier that asserts the caller must be `PoolManager`.

```
modifier poolManagerOnly() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
}
```

By applying this modifier to all hook functions, the issue may be fully mitigated.
