// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import "BoringSolidity/ERC20.sol";
import "libraries/SafeTransferLib.sol";
import "tokens/SolidlyLpWrapper.sol";
import "interfaces/ISolidlyPair.sol";
import "interfaces/IBentoBoxV1.sol";
import "interfaces/ISwapperV2.sol";

/// @notice Generic LP swapper for Abra Wrapped Solidly Volatile Pool using Matcha/0x aggregator
contract ZeroXSolidlyLikeVolatileLPSwapper is ISwapperV2 {
    using SafeTransferLib for ERC20;

    error ErrToken0SwapFailed();
    error ErrToken1SwapFailed();

    IBentoBoxV1 public immutable bentoBox;
    SolidlyLpWrapper public immutable wrapper;
    ISolidlyPair public immutable pair;
    ERC20 public immutable mim;

    address public immutable zeroXExchangeProxy;

    constructor(
        IBentoBoxV1 _bentoBox,
        SolidlyLpWrapper _wrapper,
        ERC20 _mim,
        address _zeroXExchangeProxy
    ) {
        bentoBox = _bentoBox;
        wrapper = _wrapper;
        mim = _mim;
        zeroXExchangeProxy = _zeroXExchangeProxy;
        pair = ISolidlyPair(_wrapper.underlying());

        ERC20(pair.token0()).safeApprove(_zeroXExchangeProxy, type(uint256).max);
        ERC20(pair.token1()).safeApprove(_zeroXExchangeProxy, type(uint256).max);

        mim.approve(address(_bentoBox), type(uint256).max);
    }

    /// @inheritdoc ISwapperV2
    function swap(
        address,
        address,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) public override returns (uint256 extraShare, uint256 shareReturned) {
        // 0: token0 -> MIM
        // 1: token1 -> MIM
        bytes[] memory swapData = abi.decode(data, (bytes[]));

        (uint256 amountFrom, ) = bentoBox.withdraw(ERC20(address(pair)), address(this), address(this), 0, shareFrom);

        // Wrapper -> Solidly Pair
        wrapper.leave(amountFrom);
        amountFrom = pair.balanceOf(address(this));

        // Solidly Pair -> Token0, Token1
        pair.transfer(address(pair), amountFrom);
        pair.burn(address(this));

        // token0 -> MIM
        (bool success, ) = zeroXExchangeProxy.call(swapData[0]);
        if (!success) {
            revert ErrToken0SwapFailed();
        }

        // token1 -> MIM
        (success, ) = zeroXExchangeProxy.call(swapData[1]);
        if (!success) {
            revert ErrToken1SwapFailed();
        }

        (, shareReturned) = bentoBox.deposit(mim, address(this), recipient, mim.balanceOf(address(this)), 0);
        extraShare = shareReturned - shareToMin;
    }
}