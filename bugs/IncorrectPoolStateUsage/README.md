# Vulnerability Pattern 3 - Usage of Incorrect Pool States

## Issue

While implementing complex services (e.g. automatic profit taking when prices shift past a threshold), hooks often must access the internal state of pools. This exposes the risk of pool value misuse. Straightforward value misuse is not interesting and similar to the Hook Misuse bug class. So, we will focus on a more realistic and complex case, utilizing cached stale pool states.

Starting with the use case mentioned earlier, if we want to arbitrage and realize gains with hooks, we need to perform a swap (or several swaps) after observing price changes in the pool. To observe price changes, we will hook `afterSwap,` the only place to observe any price changes.

Observant readers may see where this is going. Upon observing price changes, if we blindly throw all of our funds into arbitraging and do not properly consider what impacts the swaps might have on the observed states, chances are that there is not enough liquidity in the pool, resulting in over-swapping and a loss on the profit taker side.

```
function afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta
) external override poolManagerOnly returns (bytes4) {
    int24 lastTickLower = tickLowerLasts[key.toId()];

    (, int24 currentTick, , , , ) = poolManager.getSlot0(key.toId());
    int24 currentTickLower = _getTickLower(currentTick, key.tickSpacing);

    bool swapZeroForOne = !params.zeroForOne;

    int256 swapAmountIn;

    if (lastTickLower < currentTickLower) {
        for (int24 tick = lastTickLower; tick < currentTickLower; ) {
            swapAmountIn = takeProfitPositions[key.toId()][tick][
                swapZeroForOne
            ];
            if (swapAmountIn > 0) {
                //Each order fullfillment here shifts the currentTick, leading to later swaps functioning under unknow pool states
                fillOrder(key, tick, swapZeroForOne, swapAmountIn);
            }
            tick += key.tickSpacing;
        }
    } else {
      [...]
    }
    [...]
}
```

The example shown in [VulnHook.sol](./VulnHook.sol) is modified from one of the examples we found in the wild.

There are a lot of chances of externally sourced data misuse in hooks, but the example presented here is especially interesting to us since it is related to the dynamic pool states and a pretty common region that developers overlook.

## Mitigation

Let's start by discussing what hooks would not have those external value misusage issues.

First of all, contracts that do not rely on any external data (and do not make any external calls) would definitely not have any problem. There may still be internal logical bugs, but those are self-contained and relatively easy to catch.

Secondly, contracts that do not attempt to modify external contract states (all external contract calls are read-only) will also have fewer problems. The only part that must be appropriately handled here is the interpretation of queried data, which is also fairly simple.

This leaves us with the final case, where a hook both queries external contracts and also attempts to modify their states. In this case, there is no general way to detect/eliminate all bugs, but a simple rule of thumb is to fetch data right before utilizing it. This ensures that the data used in processing is always fresh and would not disagree with the actual value in external contracts. While repeatedly querying may be costly in terms of gas, unless developers are extremely clear about the side effects of all external calls, this is the only way to minimize the usage of incorrect values.

