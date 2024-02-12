// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Related Contracts
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";

//interfaces
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

//libraries
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

// Pool Contracts
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

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
        revert("could not find salt");
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


contract VulnHookTest is Test, Deployers{
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    VulnHook vulnHook;
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        console.log("Deploying hook.");
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(VulnHook).creationCode, abi.encode(address(manager)));
        vulnHook = new VulnHook{salt: salt}(IPoolManager(address(manager)));
        require(address(vulnHook) == hookAddress, "VulnHookTest: hook address mismatch");

        // Create the pool
        console.log("Creating the pool");
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(vulnHook));
        poolId = key.toId();
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        console.log("Provide liquidity to the pool");
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether),
            ZERO_BYTES
        );
    }

    function testFail_HookMisuse() public {
        console.log("Executing Swap of 1 ether to invoke beforeSwap hook!");

        // Perform swap //
        bool zeroForOne = true;
        int256 amountSpecified = 1e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);
        console.log("Call to swap within beforeSwap hook failed!");
    }

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
}
