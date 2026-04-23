// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {Pool} from "@ccip/contracts/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address _advancedPoolHooks, address _rmnProxy, address _router)
        TokenPool(_token, 18, _advancedPoolHooks, _rmnProxy, _router)
    {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn, 0, "", 0);
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        // For burning, we provide the pool address (this contract), not the receiver
        // It makes sense, as the pool has now taken control of the bridging flow.
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        // 1. Validate
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount, 0);
        // 2. Mint with userInterestRate data received
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);
        // 3. Return object
        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }
}

