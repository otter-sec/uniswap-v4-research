// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";

abstract contract VulnHook {
    IPoolManager public immutable poolManager;
    mapping(address caller => bool) firstTimeDonateBonus;

    error NotPoolManager();

    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: true,
                noOp: false
            });
    }

    function afterDonate(
        address sender,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external poolManagerOnly returns (bytes4) {
        if (!firstTimeDonateBonus[sender]) {
            firstTimeDonateBonus[sender] = true;
            (bool success, ) = sender.call{value: 1 ether}("");
            require(success, "send donate bonus failed");
        }
        return VulnHook.afterDonate.selector;
    }

    function fund() external payable {}
}