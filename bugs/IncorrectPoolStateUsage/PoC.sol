// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Related Contracts
import "forge-std/Test.sol";
import {MockERC20} from "v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolSwapTest} from "./deps/PoolSwapRouter.sol";

import {Constants} from "v4-core/test/utils/Constants.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import { console } from "forge-std/console.sol";
import {PoolInitializeTest} from "v4-core/src/test/PoolInitializeTest.sol";
import {PoolModifyPositionTest} from "v4-core/src/test/PoolModifyPositionTest.sol";

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

contract Deployers {
    using FeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    // Helpful test constants
    bytes constant ZERO_BYTES = new bytes(0);
    uint160 constant SQRT_RATIO_1_1 = Constants.SQRT_RATIO_1_1;
    uint160 constant SQRT_RATIO_1_2 = Constants.SQRT_RATIO_1_2;
    uint160 constant SQRT_RATIO_1_4 = Constants.SQRT_RATIO_1_4;
    uint160 constant SQRT_RATIO_4_1 = Constants.SQRT_RATIO_4_1;

    IPoolManager.ModifyPositionParams internal LIQ_PARAMS =
        IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

    // Global variables
    Currency internal currency0;
    Currency internal currency1;
    PoolManager manager;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolInitializeTest initializeRouter;

    PoolKey key;
    PoolKey nativeKey;
    PoolKey uninitializedKey;
    PoolKey uninitializedNativeKey;

    function deployFreshManager() internal {
        manager = new PoolManager(500000);
    }

    function deployFreshManagerAndRouters() internal {
        deployFreshManager();
        swapRouter = new PoolSwapTest(manager);
        modifyPositionRouter = new PoolModifyPositionTest(manager);
        initializeRouter = new PoolInitializeTest(manager);
    }

    function deployMintAndApprove2Currencies() internal returns (Currency, Currency) {
        MockERC20[] memory tokens = deployTokens(2, 1000 ether);

        address[2] memory toApprove =
            [address(swapRouter), address(modifyPositionRouter)];

        for (uint256 i = 0; i < toApprove.length; i++) {
            tokens[0].approve(toApprove[i], 1000 ether);
            tokens[1].approve(toApprove[i], 1000 ether);
        }

        return SortTokens.sort(tokens[0], tokens[1]);
    }

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (MockERC20[] memory tokens) {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", 18);
            tokens[i].mint(address(this), totalSupply);
        }
    }
}

contract VulnHookTest is Test, Deployers{
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    error NoSwapOccurred();

    VulnHook vulnHook;
    PoolId poolId;

    MockERC20 token0;
    MockERC20 token1;

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

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
        
        // Create the pool
        key = PoolKey(currency0, currency1, 0, 60, IHooks(vulnHook));
        poolId = key.toId();
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

         // Provide liquidity to the pool
        console.log("Providing liquidity to the pool");
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 60 ether),
            ZERO_BYTES
        );
        console.log("Provided liquidity to the pool");
    }

    function test_poc() public {
       // order 1 details
        int24 tick1 = 0;
        uint256 amount1 = 10 ether;
        bool zeroForOne = true;

        console.log("Placing a zeroForOne order at tick 0");
        // Place order 1 at tick 100 for 10e18 token0 tokens
        token0.approve(address(vulnHook), amount1);
        int24 tickLower1 = vulnHook.placeOrder(key, tick1, amount1, zeroForOne);

        // order 2 details
        int24 tick2 = 100;
        uint256 amount2 = 10 ether;

        console.log("Placing the second zeroForOne order at tick 100");
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

        console.log("Executing a OneForzero Swap to initate fillorder");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        console.log("Fulfilled both zeroForOne orders back to back!");
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
