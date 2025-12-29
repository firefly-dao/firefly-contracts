// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {Multicall3} from "./utils/Multicall3.sol";
import {Call3Value, Result, FireFlyerWitness} from "./utils/FireFlyStructs.sol";

contract FireFlyCaller is Multicall3 {
    using SafeTransferLib for address;

    /// @notice Revert if this contract is set as the recipient
    error InvalidRecipient(address recipient);

    /// @notice Revert if the target is invalid
    error InvalidTarget(address target);

    /// @notice Revert if the native transfer failed
    error NativeTransferFailed();

    /// @notice Revert if no recipient is set
    error NoRecipientSet();

    /// @notice Revert if the array lengths do not match
    error ArrayLengthsMismatch();

    /// @notice Revert if a call fails
    error CallFailed();

    /// @notice Protocol event to be emitted when transferring native tokens
    event SolverTransfer(address token, address to, uint256 amount);

    uint256 RECIPIENT_STORAGE_SLOT =
        uint256(keccak256("FireFlyCaller.recipient")) - 1;

    receive() external payable {
        emit SolverTransfer(address(0), address(this), msg.value);
    }

    /// @notice Execute a multicall with the FireFlyCaller as msg.sender.
    /// @dev    If a multicall is expecting to mint ERC721s or ERC1155s, the recipient must be explicitly set
    ///         All calls to ERC721s and ERC1155s in the multicall will have the same recipient set in recipient
    ///         Be sure to transfer ERC20s or ETH out of the router as part of the multicall
    /// @param calls The calls to perform
    /// @param refundTo The address to refund any leftover ETH to
    /// @param nftRecipient The address to set as recipient of ERC721/ERC1155 mints
    function multicall(
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) public payable virtual returns (Result[] memory returnData) {

        // Perform the multicall
        returnData = _aggregate3Value(calls);

        // Refund any leftover ETH to the sender
        if (address(this).balance > 0) {
            // If refundTo is address(0), refund to msg.sender
            address refundAddr = refundTo == address(0) ? msg.sender : refundTo;

            uint256 amount = address(this).balance;
            refundAddr.safeTransferETH(amount);

            emit SolverTransfer(address(0), refundAddr, amount);
        }
    }

    /// @notice Send leftover ERC20 tokens to recipients
    /// @dev    Should be included in the multicall if the router is expecting to receive tokens
    ///         Set amount to 0 to transfer the full balance
    /// @param tokens The addresses of the ERC20 tokens
    /// @param recipients The addresses to refund the tokens to
    /// @param amounts The amounts to send
    function cleanupErc20s(
        address[] calldata tokens,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) public virtual {
        // Revert if array lengths do not match
        if (
            tokens.length != amounts.length ||
            amounts.length != recipients.length
        ) {
            revert ArrayLengthsMismatch();
        }

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            address recipient = recipients[i];

            // Get the amount to transfer
            uint256 amount = amounts[i] == 0
                ? IERC20(token).balanceOf(address(this))
                : amounts[i];

            // Transfer the token to the recipient address
            token.safeTransfer(recipient, amount);
            emit SolverTransfer(token, recipient, amount);
        }
    }

    /// @notice Send leftover ERC20 tokens via explicit method calls
    /// @dev    Should be included in the multicall if the router is expecting to receive tokens
    ///         Set amount to 0 to transfer the full balance
    /// @param tokens The addresses of the ERC20 tokens
    /// @param tos The target addresses for the calls
    /// @param datas The data for the calls
    /// @param amounts The amounts to send
    function cleanupErc20sViaCall(
        address[] calldata tokens,
        address[] calldata tos,
        bytes[] calldata datas,
        uint256[] calldata amounts
    ) public virtual {
        // Revert if array lengths do not match
        if (
            tokens.length != amounts.length ||
            amounts.length != tos.length ||
            tos.length != datas.length
        ) {
            revert ArrayLengthsMismatch();
        }

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            address to = tos[i];
            bytes calldata data = datas[i];

            // Get the amount to transfer
            uint256 amount = amounts[i] == 0
                ? IERC20(token).balanceOf(address(this))
                : amounts[i];

            // First approve the target address for the call
            IERC20(token).approve(to, amount);

            // Make the call
            (bool success, ) = to.call(data);
            if (!success) {
                revert CallFailed();
            }
        }
    }

    /// @notice Send leftover native tokens to the recipient address
    /// @dev Set amount to 0 to transfer the full balance. Set recipient to address(0) to transfer to msg.sender
    /// @param amount The amount of native tokens to transfer
    /// @param recipient The recipient address
    function cleanupNative(uint256 amount, address recipient) public virtual {
        // If recipient is address(0), set to msg.sender
        address recipientAddr = recipient == address(0)
            ? msg.sender
            : recipient;

        uint256 amountToTransfer = amount == 0 ? address(this).balance : amount;
        recipientAddr.safeTransferETH(amountToTransfer);

        emit SolverTransfer(address(0), recipientAddr, amountToTransfer);
    }

    /// @notice Send leftover native tokens via an explicit method call
    /// @dev Set amount to 0 to transfer the full balance
    /// @param amount The amount of native tokens to transfer
    /// @param to The target address of the call
    /// @param data The data for the call
    function cleanupNativeViaCall(
        uint256 amount,
        address to,
        bytes calldata data
    ) public virtual {
        (bool success, ) = to.call{
            value: amount == 0 ? address(this).balance : amount
        }(data);
        if (!success) {
            revert CallFailed();
        }
    }

}
