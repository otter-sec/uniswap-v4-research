// SPDX-License-Identifier: UNLICENSED

//  forge install https://github.com/Uniswap/v4-core@06564d33b2fa6095830c914461ee64d34d39c305

pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract VulnHook is Test, IHooks, ERC1155 {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;

    mapping(PoolId poolId => int24 tickLower) public tickLowerLasts;
    mapping(uint256 tokenId => bool exists) public tokenIdExists;
    mapping(uint256 tokenId => uint256 claimable) public tokenIdClaimable;
    mapping(PoolId poolId => mapping(int24 tick => mapping(bool zeroForOne => int256 amount)))
        public takeProfitPositions;
    mapping(uint256 tokenId => uint256 supply) public tokenIdTotalSupply;
    mapping(uint256 tokenId => TokenData) public tokenIdData;

    struct TokenData {
        PoolKey poolKey;
        int24 tick;
        bool zeroForOne;
    }

    error NotPoolManager();
    error HookNotImplemented();

        
    struct HandleSwapData {
        PoolKey k;
        IPoolManager.SwapParams sp;    
    }

    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) ERC1155("") {
        poolManager = _poolManager;
    }

    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                noOp: false
            });
    }

    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external poolManagerOnly returns (bytes4) {
        _setTickLowerLast(key.toId(), _getTickLower(tick, key.tickSpacing));
        return VulnHook.afterInitialize.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external poolManagerOnly returns (bytes4) {
        int24 lastTickLower = tickLowerLasts[key.toId()];
        // console.log("slippage");
        // console.log(TickMath.MIN_SQRT_RATIO + 1);
        // console.log(TickMath.MAX_SQRT_RATIO - 1);


        console.log("lastTickLower");
        console.log(uint24(lastTickLower));

        // Get the exact current tick and use it to calculate the currentTickLower
        (, int24 currentTick, , ) = poolManager.getSlot0(key.toId());
        int24 currentTickLower = _getTickLower(currentTick, key.tickSpacing);
        console.log("currentTickLower:");
        console.log(uint24(currentTickLower));
        // We execute orders in the opposite direction
        // i.e. if someone does a zeroForOne swap to increase price of Token 1, we execute
        // all orders that are oneForZero
        // and vice versa
        bool swapZeroForOne = !params.zeroForOne;

        int256 swapAmountIn;

        // If tick has increased (i.e. price of Token 1 has increased)
        if (lastTickLower < currentTickLower) {
            console.log("inside if condition in afterSwap");
            // Loop through all ticks between the lastTickLower and currentTickLower
            // and execute all orders that are oneForZero
            for (int24 tick = lastTickLower; tick < currentTickLower; ) {
                swapAmountIn = takeProfitPositions[key.toId()][tick][
                    swapZeroForOne
                ];
                if (swapAmountIn > 0) {
                    fillOrder(key, tick, swapZeroForOne, swapAmountIn);
                }
                tick += key.tickSpacing;
            }
        }
        // Else if tick has decreased (i.e. price of Token 0 has increased)
        else {
            console.log("inside else condition in afterSwap");
            // Loop through all ticks between the lastTickLower and currentTickLower
            // and execute all orders that are zeroForOne
            for (int24 tick = lastTickLower; currentTickLower < tick; ) {
                swapAmountIn = takeProfitPositions[key.toId()][tick][
                    swapZeroForOne
                ];
                if (swapAmountIn > 0) {
                    fillOrder(key, tick, swapZeroForOne, swapAmountIn);
                }

                tick -= key.tickSpacing;
            }
        }

        tickLowerLasts[key.toId()] = currentTickLower;

        return VulnHook.afterSwap.selector;
    }

    function fillOrder(
        PoolKey calldata key,
        int24 tick,
        bool zeroForOne,
        int256 amountIn
    ) internal {
        // Setup the swapping parameters
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountIn,
            // Set the price limit to be the least possible if swapping from Token 0 to Token 1
            // or the maximum possible if swapping from Token 1 to Token 0
            // i.e. infinite slippage allowed
            sqrtPriceLimitX96: zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1
        });

        console.log("inside fill order");
 
        BalanceDelta delta = abi.decode(
            poolManager.lock(
                abi.encode(HandleSwapData(key, swapParams))
            ),
            (BalanceDelta)
        );

        // Update mapping to reflect that `amountIn` worth of tokens have been swapped from this order
        takeProfitPositions[key.toId()][tick][zeroForOne] -= amountIn;

        uint256 tokenId = getTokenId(key, tick, zeroForOne);

        // Flip the sign of the delta as tokens we were owed by Uniswap are represented as a negative delta change
        uint256 amountOfTokensReceivedFromSwap = zeroForOne
            ? uint256(int256(-delta.amount1()))
            : uint256(int256(-delta.amount0()));

        // Update the amount of tokens claimable for this order
        tokenIdClaimable[tokenId] += amountOfTokensReceivedFromSwap;
    }



    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(poolManager));
        HandleSwapData memory data = abi.decode(rawData, (HandleSwapData));

        BalanceDelta delta = this._handleSwap(data.k,data.sp);

        return abi.encode(delta);
    }

    function _handleSwap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external returns (BalanceDelta) {
        console.log("inside handle swap");

        // delta is the BalanceDelta struct that stores the delta balance changes
        // i.e. Change in Token 0 balance and change in Token 1 balance
        BalanceDelta delta = poolManager.swap(key, params, "");

        // If this swap was a swap for Token 0 to Token 1            
        if (params.zeroForOne) {
            // If we owe Uniswap Token 0, we need to send them the required amount
            if (delta.amount0() > 0) {
                IERC20(Currency.unwrap(key.currency0)).transfer(
                    address(poolManager),
                    uint128(delta.amount0())
                );
                poolManager.settle(key.currency0);
            }

            // If we are owed Token 1, we need to `take` it from the Pool Manager
            // NOTE: This will be a negative value, as it is a negative balance change from the pool's perspective
            if (delta.amount1() < 0) {
                // We flip the sign of the amount to make it positive when taking it from the pool manager
                poolManager.take(
                    key.currency1,
                    address(this),
                    uint128(-delta.amount1())
                );
            }
        }
        // Else if this swap was a swap for Token 1 to Token 0
        else {
            // Same as above
            // If we owe Uniswap Token 1, we need to send them the required amount
            if (delta.amount1() > 0) {
                IERC20(Currency.unwrap(key.currency1)).transfer(
                    address(poolManager),
                    uint128(delta.amount1())
                );
                poolManager.settle(key.currency1);
            }

            // If we are owed Token 0, we take it from the Pool Manager
            if (delta.amount0() < 0) {
                poolManager.take(
                    key.currency0,
                    address(this),
                    uint128(-delta.amount0())
                );
            }
        }

        console.log("Exiting handle swap");

        return delta;
    }
    // Core Utilities
    function placeOrder(
        PoolKey calldata key,
        int24 tick,
        uint256 amountIn,
        bool zeroForOne
    ) external returns (int24) {
        int24 tickLower = _getTickLower(tick, key.tickSpacing);
        takeProfitPositions[key.toId()][tickLower][zeroForOne] += int256(
            amountIn
        );

        uint256 tokenId = getTokenId(key, tickLower, zeroForOne);
        // If token id doesn't already exist, add it to the mapping
        // Not every order creates a new token id, as it's possible for users to add more tokens to a pre-existing order
        if (!tokenIdExists[tokenId]) {
            tokenIdExists[tokenId] = true;
            tokenIdData[tokenId] = TokenData(key, tickLower, zeroForOne);
        }

        // Mint ERC-1155 tokens to the user
        _mint(msg.sender, tokenId, amountIn, "");
        tokenIdTotalSupply[tokenId] += amountIn;

        // Extract the address of the token the user wants to sell
        address tokenToBeSoldContract = zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);


        int24 lastTickLower = tickLowerLasts[key.toId()];

        // Move the tokens to be sold from the user to this contract
        IERC20(tokenToBeSoldContract).transferFrom(
            msg.sender,
            address(this),
            amountIn
        );

        return tickLower;
    }

    function getTokenId(
        PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne
    ) public pure returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(key.toId(), tickLower, zeroForOne))
            );
    }

    function _setTickLowerLast(PoolId poolId, int24 tickLower) private {
        tickLowerLasts[poolId] = tickLower;
    }

    function _getTickLower(
        int24 actualTick,
        int24 tickSpacing
    ) private pure returns (int24) {
        int24 intervals = actualTick / tickSpacing;
        if (actualTick < 0 && actualTick % tickSpacing != 0) intervals--; // round towards negative infinity
        return intervals * tickSpacing;
    }


    function beforeDonate(address sender, PoolKey calldata key, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address sender, PoolKey calldata key, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
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

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external returns (bytes4) {
        revert HookNotImplemented();
    }

}
