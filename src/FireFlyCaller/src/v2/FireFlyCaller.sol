// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Tstorish} from "../../lib/tstorish/src/Tstorish.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuardMsgSender} from "../v1/ReentrancyGuardMsgSender.sol";
import {Multicall3} from "./utils/Multicall3.sol";
import {Call3Value, Result, FireFlyerWitness} from "./utils/FireFlyStructs.sol";

interface ITokenMessengerV1 {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external;
}

interface ITokenMessengerV2 {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external;
}

interface IMessageTransmitter {
    function receiveMessage(bytes calldata message, bytes calldata attestation)
        external
        returns (bool success);
}

contract FireFlyCaller is Multicall3, ReentrancyGuardMsgSender, Tstorish {
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
    event SolverNativeTransfer(address to, uint256 amount);

    event SolverERC20Transfer(address token, address to, uint256 amount);

    event DepositByCCTP();
    event ReceiveByCCTP();

    uint256 RECIPIENT_STORAGE_SLOT =
        uint256(keccak256("FireFlyCaller.recipient")) - 1;

    constructor() Tstorish() {}

    receive() external payable {
        emit SolverNativeTransfer(address(this), msg.value);
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
    ) public payable virtual nonReentrant returns (Result[] memory returnData) {
        // Set the NFT recipient if provided
        if (nftRecipient != address(0)) {
            _setRecipient(nftRecipient);
        }

        // Perform the multicall
        returnData = _aggregate3Value(calls);

        // Clear the recipient in storage
        _clearRecipient();

        // Refund any leftover ETH to the sender
        if (address(this).balance > 0) {
            // If refundTo is address(0), refund to msg.sender
            address refundAddr = refundTo == address(0) ? msg.sender : refundTo;

            uint256 amount = address(this).balance;
            refundAddr.safeTransferETH(amount);

            emit SolverNativeTransfer(refundAddr, amount);
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
            emit SolverERC20Transfer(token, recipient, amount);
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

    function receiveByCCTP(
        bytes calldata message,
        bytes calldata attestation,
        address targetContract
    ) external payable {
        IMessageTransmitter(targetContract).receiveMessage(
            message,
            attestation
        );
        emit ReceiveByCCTP();
    }

    function depositByCCTP(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        uint256 dtc,
        address maker,
        address targetContract
    ) external payable {
        require(amount > dtc, "Amount must be greater than fee");

        uint256 value = amount - dtc;
        IERC20(burnToken).transfer(maker, dtc);
        IERC20(burnToken).approve(targetContract, 0);
        IERC20(burnToken).approve(targetContract, value);
        if (maxFee == 0) {
            ITokenMessengerV1(targetContract).depositForBurn(
                value,
                destinationDomain,
                mintRecipient,
                burnToken
            );
        } else {
            ITokenMessengerV2(targetContract).depositForBurn(
                value,
                destinationDomain,
                mintRecipient,
                burnToken,
                destinationCaller,
                maxFee,
                minFinalityThreshold
            );
        }

        emit DepositByCCTP();
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

        emit SolverNativeTransfer(recipientAddr, amountToTransfer);
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

    /// @notice Internal function to set the recipient address for ERC721 or ERC1155 mint
    /// @dev If the chain does not support tstore, recipient will be saved in storage
    /// @param recipient The address of the recipient
    function _setRecipient(address recipient) internal {
        // For safety, revert if the recipient is this contract
        // Tokens should either be minted directly to recipient, or transferred to recipient through the onReceived hooks
        if (recipient == address(this)) {
            revert InvalidRecipient(address(this));
        }

        // Set the recipient in storage
        _setTstorish(RECIPIENT_STORAGE_SLOT, uint256(uint160(recipient)));
    }

    /// @notice Internal function to get the recipient address for ERC721 or ERC1155 mint
    function _getRecipient() internal view returns (address) {
        // Get the recipient from storage
        return address(uint160(_getTstorish(RECIPIENT_STORAGE_SLOT)));
    }

    /// @notice Internal function to clear the recipient address for ERC721 or ERC1155 mint
    function _clearRecipient() internal {
        // Return if recipient hasn't been set
        if (_getRecipient() == address(0)) {
            return;
        }

        // Clear the recipient in storage
        _clearTstorish(RECIPIENT_STORAGE_SLOT);
    }

    function onERC721Received(
        address, /*_operator*/
        address, /*_from*/
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        // Get the recipient from storage
        address recipient = _getRecipient();

        // Revert if no recipient is set
        // Note this means transferring NFTs to this contract via `safeTransferFrom` will revert,
        // unless the transfer is part of a multicall that sets the recipient in storage
        if (recipient == address(0)) {
            revert NoRecipientSet();
        }

        // Transfer the NFT to the recipient
        IERC721(msg.sender).safeTransferFrom(
            address(this),
            recipient,
            _tokenId,
            _data
        );

        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address, /*_operator*/
        address, /*_from*/
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes4) {
        // Get the recipient from storage
        address recipient = _getRecipient();

        // Revert if no recipient is set
        // Note this means transferring NFTs to this contract via `safeTransferFrom` will revert,
        // unless the transfer is part of a multicall that sets the recipient in storage
        if (recipient == address(0)) {
            revert NoRecipientSet();
        }

        // Transfer the tokens to the recipient
        IERC1155(msg.sender).safeTransferFrom(
            address(this),
            recipient,
            _id,
            _value,
            _data
        );

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /*_operator*/
        address, /*_from*/
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external returns (bytes4) {
        // Get the recipient from storage
        address recipient = _getRecipient();

        // Revert if no recipient is set
        // Note this means transferring NFTs to this contract via `safeTransferFrom` will revert,
        // unless the transfer is part of a multicall that sets the recipient in storage
        if (recipient == address(0)) {
            revert NoRecipientSet();
        }

        // Transfer the tokens to the recipient
        IERC1155(msg.sender).safeBatchTransferFrom(
            address(this),
            recipient,
            _ids,
            _values,
            _data
        );

        return this.onERC1155BatchReceived.selector;
    }
}
