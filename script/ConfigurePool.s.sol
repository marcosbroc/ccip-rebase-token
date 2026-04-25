// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken,
        bool outboundLimiterRateIsEnabled,
        uint128 outboundLimiterCapacity,
        uint128 outboundLimiterRate,
        bool inboundLimiterRateIsEnabled,
        uint128 inboundLimiterCapacity,
        uint128 inboundLimiterRate
    ) public {
        vm.startBroadcast();
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundLimiterRateIsEnabled, capacity: outboundLimiterCapacity, rate: outboundLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundLimiterRateIsEnabled, capacity: inboundLimiterCapacity, rate: inboundLimiterRate
            })
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
        vm.stopBroadcast();
    }
}

/*

struct RemoteChainConfig {
  RateLimiter.TokenBucket outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain.
  RateLimiter.TokenBucket inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain.
  bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
  EnumerableSet.Bytes32Set remotePools; // Set of remote pool hashes, ABI encoded in the case of a remote EVM chain.
}

struct RateLimitConfigArgs {
  uint64 remoteChainSelector; // Remote chain selector.
  bool customBlockConfirmations; // Whether the rate limit config is for custom block confirmations transfers.
  RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limiter configuration.
  RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limiter configuration.
}*/
