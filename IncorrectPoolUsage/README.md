# Vulnerability Pattern 3 - Usage of Incorrect Pool Values

## Issue

While implementing complex services (e.g. automatic profit taking when prices shift past a threshold), hooks often have to access the internal state of pools. This exposes the risk of pool value misuse. Straightforward value misuse is not interesting, and pretty similar to the Hook Misuse bug class. So we're going to focus on more realistic / complex case here, which usage of cached stale pool states.

Starting with the use case mentioned earlier, if we want to arbitrage and realize gains with hooks, we need to perform a swap (or several swaps) after observing price changes in the pool. To observe price changes, we will hook `afterSwap`, which is the only place that will observe any price changes.

Observant readers might see where this is going, upon observing price changes, if we blindly throw all of our funds into arbitraging, and do not properly consider what impacts the swaps might have on the observed states, chances are that the there is not enough liquidity in the pool, leading to over-swapping and a loss on the profit taker side.

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

The example shown in [vuln.sol]() is modified from one of the examples we found in the wild.

There are a lot of chances of external sourced data misuse in hooks, but the example presented here is especially interesting to us since it is related to the dynamic pool states, and a pretty common region to be overlooked by developers.

## Mitigation

Let's start of with discussing what kind of hooks would not have those external value misusage issues.

First of all, contracts that do not rely on any external data (and does not make any external calls) would definitely not have any problem. There might still be internal logical bugs, but those are self contained, and relatively easy to catch.

Secondly, contracts that do not attempt to modify external contracts states (all external contracts calls are read only) will also have less problems. The only part that need to be handled properly here is interpretation of queried data, which is also fairly simple.

This leaves us with the final case, where a hook both queries external contracts and also attempts to modify their states. In this case, there is no general way to detect / eliminate all bugs, but a simple thumb of rule is to fetch data right before using. This ensures that the data used in processing is always fresh and would not disagree with actual value in external contracts. While repeatedly querying may turn out to be costly in terms of gas, unless developers are extremely clear about the side affects of all external calls, this is the only way to minimize usage of incorrect values.

## In the wild examples
