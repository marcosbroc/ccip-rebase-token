// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 SEND_VALUE = 1e5;

    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken ethSepoliaToken;
    RebaseToken arbSepoliaToken;
    Vault vault;
    RebaseTokenPool ethSepoliaPool;
    RebaseTokenPool arbSepoliaPool;
    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        ethSepoliaFork = vm.createSelectFork("eth-sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deploy and configure on Ethereum Sepolia
        console.log("***** DEPLOYING POOL ON ETH SEPOLIA, CHAIN ID: ", block.chainid);
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        ethSepoliaPool = new RebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            address(0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );
        ethSepoliaToken.grantMintAndBurnRole(address(vault));
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaPool));
        RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(ethSepoliaToken));
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethSepoliaToken));
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(ethSepoliaToken), address(ethSepoliaPool));
        vm.stopPrank();

        // 2. Deploy and configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        console.log("***** DEPLOYING POOL ON ETH ARBITRUM, CHAIN ID: ", block.chainid);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            address(0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();

        // Create local ETH SEPOLIA POOL
        configureTokenPool(
            ethSepoliaFork,
            address(ethSepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        // Create remote ARBITRUM SEPOLIA POOL
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            ethSepoliaNetworkDetails.chainSelector,
            address(ethSepoliaPool),
            address(ethSepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        vm.prank(owner);
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    /**
     *
     * @param amountToBridge The amount to bridge
     * @param localFork The local fork
     * @param remoteFork The remote fork
     * @param localNetworkDetails The local network details
     * @param remoteNetworkDetails The remote network details
     * @param localToken The local token
     * @param remoteToken The remote token
     */
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        // Create the struct containing the message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // Ask the source router what the fee is
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // Pretend we have the LINK fee
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        // Allow source router to spend the fee
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // Allow source router to send the amount
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        uint256 localBalanceBefore = localToken.balanceOf(user);

        // Send the message crosschain via the source router
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        // Check balance has been deducted
        assertEq(localToken.balanceOf(user), localBalanceBefore - amountToBridge);

        // Check interest rate on source
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        // Get the remote balance before transferring
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        vm.selectFork(localFork);

        // Switch chain and route message
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // Check current remote balance is now the same as previous balance + amount
        assertEq(remoteToken.balanceOf(user), remoteBalanceBefore + amountToBridge);

        // Check interest rate on destination
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);

        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(ethSepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(ethSepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            ethSepoliaToken,
            arbSepoliaToken
        );
    }

    function testBridgeBackAndForth() public {
        vm.selectFork(ethSepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(ethSepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            ethSepoliaToken,
            arbSepoliaToken
        );
        vm.selectFork(ethSepoliaFork);
        console.log("Local balance after bridging:", ethSepoliaToken.balanceOf(user));
        vm.selectFork(arbSepoliaFork);
        console.log("Remote balance after bridging:", arbSepoliaToken.balanceOf(user));

        // Send half back to source chain
        bridgeTokens(
            SEND_VALUE / 2,
            arbSepoliaFork,
            ethSepoliaFork,
            arbSepoliaNetworkDetails,
            ethSepoliaNetworkDetails,
            arbSepoliaToken,
            ethSepoliaToken
        );

        vm.selectFork(ethSepoliaFork);
        console.log("Local balance after bridging back:", ethSepoliaToken.balanceOf(user));
        vm.selectFork(arbSepoliaFork);
        console.log("Remote balance after bridging back:", arbSepoliaToken.balanceOf(user));
    }
}
