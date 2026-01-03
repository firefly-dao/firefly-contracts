// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Call3Value, Result} from "./FireFlyStructs.sol";

/// @title Multicall3
/// @notice Aggregate results from multiple function calls
/// @dev Multicall & Multicall2 backwards-compatible
/// @dev Aggregate methods are marked `payable` to save 24 gas per call
/// @dev This is a fork of the original Multicall3 contract with multicalls
/// @dev only executable by address(this). This contract is meant to be inherited
/// @dev by other contracts that need to perform multicalls.
/// @author Michael Elliot <mike@makerdao.com>
/// @author Joshua Levine <joshua@makerdao.com>
/// @author Nick Johnson <arachnid@notdot.net>
/// @author Andreas Bigger <andreas@nascent.xyz>
/// @author Matt Solomon <matt@mattsolomon.dev>
contract Multicall3 {
    event SolverCallExecuted(address to, bytes data, uint256 amount);

    /// @notice Aggregate calls
    /// @param calls An array of Call3Value structs
    /// @return returnData An array of Result structs
    function _aggregate3Value(
        Call3Value[] calldata calls
    ) internal returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call3Value calldata calli;

        for (uint256 i = 0; i < length; ) {
            Result memory result = returnData[i];
            calli = calls[i];

            uint256 val = calli.value;
            (result.success, result.returnData) = calli.target.call{value: val}(
                calli.callData
            );

            assembly {
                // Revert if the call fails and failure is not allowed
                // `allowFailure := calldataload(add(calli, 0x20))` and `success := mload(result)`
                if iszero(or(calldataload(add(calli, 0x20)), mload(result))) {
                    // Set "Error(string)" signature: bytes32(bytes4(keccak256("Error(string)")))
                    mstore(
                        0x00,
                        0x08c379a000000000000000000000000000000000000000000000000000000000
                    )
                    // set data offset
                    mstore(
                        0x04,
                        0x0000000000000000000000000000000000000000000000000000000000000020
                    )
                    // Set length of revert string
                    mstore(
                        0x24,
                        0x0000000000000000000000000000000000000000000000000000000000000017
                    )
                    // Set revert string: bytes32(abi.encodePacked("Multicall3: call failed"))
                    mstore(
                        0x44,
                        0x4d756c746963616c6c333a2063616c6c206661696c6564000000000000000000
                    )
                    revert(0x00, 0x84)
                }
            }

            if (result.success) {
                emit SolverCallExecuted(
                    calli.target,
                    calli.callData,
                    calli.value
                );
            }

            unchecked {
                ++i;
            }
        }
    }
}
