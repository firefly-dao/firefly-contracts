// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {IPermit2} from "../../lib/permit2-firefly/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "../../lib/permit2-firefly/src/interfaces/ISignatureTransfer.sol";
import {TrustlessPermit} from "../../lib/trustlessPermit/TrustlessPermit.sol";
import {IFireFlyCaller} from "./interfaces/IFireFlyCaller.sol";
import {Call3Value, Permit, Result, Depositors} from "./utils/FireFlyStructs.sol";

contract FireFlyRouter is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SignatureCheckerLib for address;
    using TrustlessPermit for address;

    error NotOwnerError();
    error LengthError();
    error ZeroAddressError();
    error AmountError();
    error TargetError();
    error CallError();
    error EmptyArrayError();
    error Unauthorized();

    event Deposit(address indexed token, address indexed maker, uint256 amount);
    event CrossChainTransfer(string fromChain, string fromHash);
    event SolverNativeTransfer(address to, uint256 amount);
    event DepositByCCTP();
    event ReceiveByCCTP();

    /// @notice Revert if the array lengths do not match
    error ArrayLengthsMismatch();

    /// @notice Revert if the native transfer fails
    error NativeTransferFailed();

    /// @notice Revert if the refundTo address is zero address
    error RefundToCannotBeZeroAddress();

    /// @notice Emit event when the router is updated
    event RouterUpdated(address newRouter);

    /// @notice Emit event when the Permit2 address is updated
    event Permit2Updated(address newPermit2);

    /// @notice The address of the router contract
    address public router;

    /// @notice The Permit2 contract
    IPermit2 private PERMIT2;

    bytes32 public constant _CALL3VALUE_TYPEHASH =
        keccak256(
            "Call3Value(address target,bool allowFailure,uint256 value,bytes callData)"
        );
    string public constant _FIREFLYER_WITNESS_TYPE_STRING =
        "FireFlyerWitness witness)Call3Value(address target,bool allowFailure,uint256 value,bytes callData)FireFlyerWitness(address fireflyer,address refundTo,address nftRecipient,Call3Value[] call3Values)TokenPermissions(address token,uint256 amount)";
    bytes32 public constant _EIP_712_FIREFLYER_WITNESS_TYPE_HASH =
        keccak256(
            "FireFlyerWitness(address fireflyer,address refundTo,address nftRecipient,Call3Value[] call3Values)Call3Value(address target,bool allowFailure,uint256 value,bytes callData)"
        );

    receive() external payable {}


    function initialize(
        address _owner,
        address _router,
        address _permit2
    ) public initializer {
        __Ownable_init(_owner);
        router = _router;
        PERMIT2 = IPermit2(_permit2);
    }

    /// @notice Withdraw function in case funds get stuck in contract
    function withdraw() external onlyOwner {
        _send(msg.sender, address(this).balance);
    }

    /// @notice Set the router address
    /// @param _router The address of the router contract
    function setRouter(address _router) external onlyOwner {
        router = _router;

        emit RouterUpdated(_router);
    }

    /// @notice Set the Permit2 address
    /// @param _permit2 The address of the Permit2 contract
    function setPermit2(address _permit2) external onlyOwner {
        PERMIT2 = IPermit2(_permit2);

        emit Permit2Updated(_permit2);
    }

    function depositAndMulticall(
        address token,
        Call3Value[] calldata calls,
        Depositors[] memory depositors,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        uint256 amount = 0;
        for (uint256 i = 0; i < depositors.length; i++) {
            Depositors memory info = depositors[i];
            if (bytes(info.target).length == 0) revert TargetError();
            amount += info.dstAmount;
        }

        if (token == address(0)) {
            if (msg.value != amount) {
                revert AmountError();
            }
        } else {
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= amount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, router, amount);
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
    }

    function deposit(
        address token,
        address maker,
        uint256 channel,
        Depositors[] memory depositors
    ) external payable {
        if (depositors.length == 0) revert EmptyArrayError();

        uint256 amount = 0;
        for (uint256 i = 0; i < depositors.length; i++) {
            Depositors memory info = depositors[i];
            if (bytes(info.target).length == 0) revert TargetError();
            amount += info.dstAmount;
        }

        if (token == address(0)) {
            if (msg.value != amount) {
                revert AmountError();
            }
            (bool ok, ) = maker.call{value: amount}("");
            if (!ok) {
                revert CallError();
            }
            emit SolverNativeTransfer(maker, amount);
        } else {
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= amount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, maker, amount);
        }
    }

    function receiveAndForward(
        address token,
        address dstAddress,
        uint256 tokenAmount
    ) external payable {
        if (token == address(0)) {
            if (msg.value != tokenAmount) {
                revert AmountError();
            }
            (bool ok, ) = dstAddress.call{value: msg.value}("");
            if (!ok) {
                revert CallError();
            }
            emit SolverNativeTransfer(dstAddress, tokenAmount);
        } else {
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= tokenAmount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, dstAddress, tokenAmount);
        }
    }

    function receiveAndForwardMulticall(
        address token,
        uint256 amount,
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        if (token == address(0)) {
            if (msg.value != amount) {
                revert AmountError();
            }
        } else {
            // Transfer the tokens to the router
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= amount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, router, amount);
        }
        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
    }

    /// @notice Use ERC2612 permit to transfer tokens to FireFlyCaller and execute multicall in a single tx
    /// @dev    Approved spender must be address(this) to transfer user's tokens to the FireFlyCaller. If leftover ETH
    ///         is expected as part of the multicall, be sure to set refundTo to the expected recipient. If the multicall
    ///         includes ERC721/ERC1155 mints or transfers, be sure to set nftRecipient to the expected recipient.
    /// @param permits An array of permits
    /// @param calls The calls to perform
    /// @param refundTo The address to refund any leftover ETH to
    /// @param nftRecipient The address to set as recipient of ERC721/ERC1155 mints
    /// @return returnData The return data from the multicall
    function permitTransferAndMulticall(
        Permit[] calldata permits,
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        for (uint256 i = 0; i < permits.length; i++) {
            Permit memory permit = permits[i];

            // Revert if the permit owner is not the msg.sender
            if (permit.owner != msg.sender) {
                revert Unauthorized();
            }

            // Use the permit. Calling `trustlessPermit` allows tx to
            // continue even if permit gets frontrun
            permit.token.trustlessPermit(
                permit.owner,
                address(this),
                permit.value,
                permit.deadline,
                permit.v,
                permit.r,
                permit.s
            );

            // Transfer the tokens to the router
            IERC20(permit.token).safeTransferFrom(
                permit.owner,
                router,
                permit.value
            );
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
    }

    /// @notice Use Permit2 to transfer tokens to FireFlyCaller and perform an arbitrary multicall.
    ///         Pass in an empty permitSignature to only perform the multicall.
    /// @dev    msg.value will persist across all calls in the multicall. If leftover ETH is expected
    ///         as part of the multicall, be sure to set refundTo to the expected recipient. If the multicall
    ///         includes ERC721/ERC1155 mints or transfers, be sure to set nftRecipient to the expected recipient.
    /// @param user The address of the user
    /// @param permit The permit details
    /// @param calls The calls to perform
    /// @param refundTo The address to refund any leftover ETH to
    /// @param nftRecipient The address to set as recipient of ERC721/ERC1155 mints
    /// @param permitSignature The signature for the permit
    function permit2TransferAndMulticall(
        address user,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient,
        bytes memory permitSignature
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        // If a permit signature is provided, use it to transfer tokens from user to router
        if (permitSignature.length != 0) {
            _handleBatchPermit(
                user,
                refundTo,
                nftRecipient,
                permit,
                calls,
                permitSignature
            );
        }

        // Perform the multicall and send leftover to refundTo
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
    }

    /// @notice Internal function to handle a permit batch transfer
    /// @param user The address of the user
    /// @param refundTo The address to refund any leftover ETH to
    /// @param nftRecipient The address to set as recipient of ERC721/ERC1155 mints
    /// @param permit The permit details
    /// @param calls The calls to perform
    /// @param permitSignature The signature for the permit
    function _handleBatchPermit(
        address user,
        address refundTo,
        address nftRecipient,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        Call3Value[] calldata calls,
        bytes memory permitSignature
    ) internal {
        // Create an array of keccak256 hashes of the call3Values
        bytes32[] memory call3ValuesHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            // Encode the call3Value and hash it
            // @dev callData must be hashed before encoding since it is a dynamic type
            call3ValuesHashes[i] = keccak256(
                abi.encode(
                    _CALL3VALUE_TYPEHASH,
                    calls[i].target,
                    calls[i].allowFailure,
                    calls[i].value,
                    keccak256(calls[i].callData)
                )
            );
        }

        // Create the witness that should be signed over
        bytes32 witness = keccak256(
            abi.encode(
                _EIP_712_FIREFLYER_WITNESS_TYPE_HASH,
                msg.sender,
                refundTo,
                nftRecipient,
                keccak256(abi.encodePacked(call3ValuesHashes))
            )
        );

        // Create the SignatureTransferDetails array
        ISignatureTransfer.SignatureTransferDetails[]
            memory signatureTransferDetails = new ISignatureTransfer.SignatureTransferDetails[](
                permit.permitted.length
            );
        for (uint256 i = 0; i < permit.permitted.length; i++) {
            uint256 amount = permit.permitted[i].amount;

            signatureTransferDetails[i] = ISignatureTransfer
                .SignatureTransferDetails({
                    to: address(router),
                    requestedAmount: amount
                });
        }

        // Use the SignatureTransferDetails and permit signature to transfer tokens to the router
        PERMIT2.permitWitnessTransferFrom(
            permit,
            signatureTransferDetails,
            // When using a permit signature, cannot deposit on behalf of someone else other than `user`
            user,
            witness,
            _FIREFLYER_WITNESS_TYPE_STRING,
            permitSignature
        );
    }

    function _send(address to, uint256 value) internal {
        bool success;
        assembly {
            // Save gas by avoiding copying the return data to memory.
            // Provide at most 100k gas to the internal call, which is
            // more than enough to cover common use-cases of logic for
            // receiving native tokens (eg. SCW payable fallbacks).
            success := call(100000, to, value, 0, 0, 0, 0)
        }

        if (!success) {
            revert NativeTransferFailed();
        }
    }
}
