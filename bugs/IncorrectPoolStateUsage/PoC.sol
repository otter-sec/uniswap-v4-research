// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Related Contracts
import "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {MockERC20} from "v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import { console } from "forge-std/console.sol";
import {PoolInitializeTest} from "v4-core/src/test/PoolInitializeTest.sol";
import {PoolModifyPositionTest} from "v4-core/src/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {ProtocolFeeControllerTest} from "v4-core/src/test/ProtocolFeeControllerTest.sol";

//interfaces
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "v4-core/src/interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

//libraries
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {FeeLibrary} from "v4-core/src/libraries/FeeLibrary.sol";

// Pool Contracts
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";

// Vulnerable Hook Contract 
import {VulnHook} from "./VulnHook.sol";

library HookMiner {
    uint160 constant FLAG_MASK = 0xFFF << 148;

    uint256 constant MAX_LOOP = 20_000;

    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        external
        view
        returns (address, bytes32)
    {
        address hookAddress;
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        uint256 salt;
        for (salt; salt < MAX_LOOP; salt++) {
            hookAddress = computeAddress(deployer, salt, creationCodeWithArgs);
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, bytes32(salt));
            }
        }
        revert("Could not find salt");
    }

    function computeAddress(address deployer, uint256 salt, bytes memory creationCode)
        public
        pure
        returns (address hookAddress)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, salt, keccak256(creationCode)))))
        );
    }
}

contract VulnHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    VulnHook vulnHook;
    PoolId poolId;

    MockERC20 token0;
    MockERC20 token1;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(VulnHook).creationCode, abi.encode(address(manager)));
        vulnHook = new VulnHook{salt: salt}(IPoolManager(address(manager)));
        require(address(vulnHook) == hookAddress, "VulnHookTest: hook address mismatch");

        // (currency0, currency1) = SortTokens.sort(tokenA, tokenB);
        

        // Create the pool
        key = PoolKey(currency0, currency1, 0, 60, IHooks(vulnHook));
        poolId = key.toId();
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

         // Provide liquidity to the pool
        console.log("Provide liquidity to the pool");
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 50 ether),
            ZERO_BYTES
        );
        console.log("Provided liquidity to the pool");

    }

function test_poc() public {
        // order 1 details
        int24 tick1 = 120;
        uint256 amount1 = 10 ether;
        bool zeroForOne = true;

        // Place order 1 at tick 100 for 10e18 token0 tokens
        token0.approve(address(vulnHook), amount1);
        int24 tickLower1 = vulnHook.placeOrder(key, tick1, amount1, zeroForOne);

        // order 2 details
        int24 tick2 = 120;
        uint256 amount2 = 10 ether;

        // Place order 2 at tick 120 for 10e18 token0 tokens
        token0.approve(address(vulnHook), amount2);
        int24 tickLower2 = vulnHook.placeOrder(key, tick2, amount2, zeroForOne);

        // Do a separate swap from oneForZero to make tick go up
        // Sell 1e18 token1 tokens for token0 tokens
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: !zeroForOne,
            amountSpecified: 10 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // Check that the order has been executed
        int256 tokensLeftToSell = vulnHook.takeProfitPositions(
            poolId,
            tick,
            zeroForOne
        );
        assertEq(tokensLeftToSell, 0);
    }


//  function test_placeOrder() public {
//         // Place a zeroForOne take-profit order
//         // for 10e18 token0 tokens
//         // at tick 100

//         int24 tick = 100;
//         uint256 amount = 10 ether;
//         bool zeroForOne = true;

//         // Note the original balance of token0 we have
//         uint256 originalBalance = token0.balanceOf(address(this));

//         // Place the order
//         token0.approve(address(vulnHook), amount);
//         int24 tickLower = vulnHook.placeOrder(key, tick, amount, zeroForOne);

//         // Note the new balance of token0 we have
//         uint256 newBalance = token0.balanceOf(address(this));

//         // Do a separate swap from oneForZero to make tick go up
//         // Sell 1e18 token1 tokens for token0 tokens
//         IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
//             zeroForOne: !zeroForOne,
//             amountSpecified: 20 ether,
//             sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
//         });

//         PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
//             .TestSettings({withdrawTokens: true, settleUsingTransfer: true});

//         swapRouter.swap(key, params, testSettings, ZERO_BYTES);

//         // Since we deployed the pool contract with tick spacing = 60
//         // i.e. the tick can only be a multiple of 60
//         // and initially the tick is 0
//         // the tickLower should be 60 since we placed an order at tick 100
//         assertEq(tickLower, 60);

//         // Ensure that our balance was reduced by `amount` tokens
//         assertEq(originalBalance - newBalance, amount);

//         // Check the balance of ERC-1155 tokens we received
//         uint256 tokenId = vulnHook.getTokenId(key, tickLower, zeroForOne);
//         uint256 tokenBalance = vulnHook.balanceOf(address(this), tokenId);

//         // Ensure that we were, in fact, given ERC-1155 tokens for the order
//         // equal to the `amount` of token0 tokens we placed the order for
//         assertTrue(tokenId != 0);
//         assertEq(tokenBalance, amount);
//     }

    function swap(
        PoolKey memory key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1 
        });

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        delta = swapRouter.swap(key, params, testSettings, hookData);
    }
 
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
                )
            );
    }
}
  
