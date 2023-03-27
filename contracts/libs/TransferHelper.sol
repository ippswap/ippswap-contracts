
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library TransferHelper {
    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value : value}(new bytes(0));
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
    }
}