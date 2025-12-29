// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title ReentrancyGuardMsgSender_NonTstore
/// @notice Modified version of OpenZeppelin's ReentrancyGuardTransient
///         https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuardTransient.sol
/// @dev ReentrancyGuardMsgSender stores the original, non-reentrant msg.sender in transient storage.
///      Allows the original sender and the contract itself to reenter the contract, but prevents all other callers from reentering.
abstract contract ReentrancyGuardMsgSender_NonTstore {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MSG_SENDER_STORAGE_SLOT =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    /// @notice Unauthorized reentrant call
    error InvalidMsgSender(address storedSender, address actualSender);

    constructor() {}

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        address sender = msg.sender;

        // Load the stored sender from the transient slot
        address storedSender;
        assembly ("memory-safe") {
            storedSender := sload(MSG_SENDER_STORAGE_SLOT)
        }

        // Revert if sender slot has been set and is not the same as the caller
        // Allow contract to reenter itself
        if (storedSender != address(0) && storedSender != sender && sender != address(this)) {
            revert InvalidMsgSender(storedSender, sender);
        }

        // Any calls to nonReentrant after this point will fail
        assembly ("memory-safe") {
            sstore(MSG_SENDER_STORAGE_SLOT, sender)
        }
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see https://eips.ethereum.org/EIPS/eip-2200)
        address zeroAddress = address(0);
        assembly ("memory-safe") {
            sstore(MSG_SENDER_STORAGE_SLOT, zeroAddress)
        }
    }
}
