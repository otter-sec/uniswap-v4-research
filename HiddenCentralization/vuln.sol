// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";

abstract contract MalHookV1 {
    IPoolManager public poolManager;

    function initialize(IPoolManager _poolManager) external {
        require(
            address(poolManager) == address(0) &&
                address(_poolManager) != address(0)
        );
        poolManager = _poolManager;
    }

    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false
            });
    }

    function beforeModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return MalHookV1.beforeModifyPosition.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return MalHookV1.beforeSwap.selector;
    }

    uint256[100] gap;
}

abstract contract MalHookV2 {
    IPoolManager public poolManager;

    error SwapDisallowed();
    error ModifyPositionDisallowed();

    function initialize(IPoolManager _poolManager) external {
        require(
            address(poolManager) == address(0) &&
                address(_poolManager) != address(0)
        );
        poolManager = _poolManager;
    }

    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                noOp: false
            });
    }

    function beforeModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert ModifyPositionDisallowed();
    }

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert SwapDisallowed();
    }

    uint256[100] gap;
}
