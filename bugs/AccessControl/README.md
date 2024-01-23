# Vulnerability Pattern 1 - Lack Of Access Control

## Issue

Since hooks are used to handle supplementary logic for pools, there is a high chance that the hook contract must maintain its own state. Similarly, if any malicious parties are able to manipulate the storage within the contract, it might lead to exploitable bugs.

A common source of contract mismanagement is lack of access control. In the context of univ4 hooks, we have several external facing functions (hooks) that should only be called by the `PoolManager`. If any of those functions modify the hook contract state but does not limit its caller, attackers may directly call them leading to unexpected manipulation of contract state.

We present a minimal example of this in [vuln.sol](), where the `swapCnt` counter is used to track total swaps performed on the `Pool`, but can be manipulated by users who directly call `beforeSwap` due to lack of access control.

## Mitigation

While this is the most widespread bug we found in public hook implementations (~50% didn't properly check caller), it is also easily fixable. In fact, [BaseHook.sol](https://github.com/Uniswap/v4-periphery/blob/886403181f707f9645d59d47180cca042bc4eb87/contracts/BaseHook.sol) provided by uniswap already contains a `poolManagerOnly` modifier that asserts the caller must be `PoolManager`.

```
modifier poolManagerOnly() {
    if (msg.sender != address(poolManager)) revert NotPoolManager();
    _;
}
```

By applying this modifier to all hook functions, we can fully mitigate the issue.

## In the wild examples
https://github.com/Uniswap/v4-periphery/blob/63d64fcd82bff9ec0bad89730ce28d7ffa8e4225/contracts/hooks/examples/FullRange.sol#L233
https://github.com/atj3097/mfa-multisig-hook-v4/blob/b386d8b32861626cace848ef1f8757fe1b79cbed/src/MultiSigSwapHook.sol#L66
https://github.com/ArrakisFinance/uni-v4-playground/blob/5cf3b3e4729253303dce2818bc8a3a47f25903f7/contracts/ArrakisHookV1.sol#L79
