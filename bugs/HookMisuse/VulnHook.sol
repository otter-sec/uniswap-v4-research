// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {console} from "forge-std/console.sol";


contract VulnHook is IHooks{
    using PoolIdLibrary for PoolKey;

    error NotPoolManager();
    error HookNotImplemented();

    bytes constant ZERO_BYTES = new bytes(0);

    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            noOp: false
        });
    }

    // -------
    // HOOKS
    // -------

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        returns (bytes4)
    {
        bool zeroForOne = true;
        int256 amountSpecified = 1e18;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1 // unlimited impact
        });

        BalanceDelta delta = poolManager.swap(key, params,ZERO_BYTES );
        return VulnHook.beforeSwap.selector;
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
  
    function beforeModifyPosition(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterModifyPosition(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4){
        revert HookNotImplemented();
    }

    function beforeDonate(address sender, PoolKey calldata key, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
    
    function afterDonate(address, PoolKey calldata key, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
}
