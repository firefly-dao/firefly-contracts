// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Call3Value, Result} from "../utils/FireFlyStructs.sol";

interface IFireFlyCaller {
    function multicall(
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData);

    function cleanupErc20s(
        address[] calldata tokens,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    function cleanupNative(uint256 amount, address recipient) external;
}
