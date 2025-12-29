// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;
import {TransientSlot} from "./TransientSlot.sol";

/// @title ReentrancyGuardMsgSender
/// @notice Modified version of OpenZeppelin's ReentrancyGuardTransient
///         https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol
/// @dev ReentrancyGuardMsgSender stores the original, nonreentrant msg.sender in transient storage. Allows the original sender
///      and the contract itself to reenter the contract, but prevents all other callers from reentering.
abstract contract ReentrancyGuardMsgSender {
    using TransientSlot for *;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 MSG_SENDER_STORAGE_SLOT =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    /**
     * @dev Unauthorized reentrant call.
     */
    error InvalidMsgSender(address storedSender, address actualSender);

    constructor() {}

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // Load the stored sender from the transient slot
        address storedSender = MSG_SENDER_STORAGE_SLOT.asAddress().tload();

        // Revert if sender slot has been set and is not the same as the caller
        // Allow contract to reenter itself
        if (
            storedSender != address(0) &&
            storedSender != msg.sender &&
            msg.sender != address(this)
        ) {
            revert InvalidMsgSender(storedSender, msg.sender);
        }

        // Any calls to nonReentrant after this point will fail
        MSG_SENDER_STORAGE_SLOT.asAddress().tstore(msg.sender);
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        MSG_SENDER_STORAGE_SLOT.asAddress().tstore(address(0));
    }
}
