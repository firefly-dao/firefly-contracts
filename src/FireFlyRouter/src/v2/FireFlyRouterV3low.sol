// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {IPermit2} from "../../lib/permit2-firefly/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "../../lib/permit2-firefly/src/interfaces/ISignatureTransfer.sol";
import {TrustlessPermit} from "../../lib/trustlessPermit/TrustlessPermit.sol";
import {IFireFlyCaller} from "./interfaces/IFireFlyCaller.sol";
import {Call3Value, Permit, Result, Depositors} from "./utils/FireFlyStructs.sol";

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
}

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContractt(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     *
     * _Available since v2.4.0._
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }
}

library SafeERC20 {
    using Address for address;
    using SafeMath for uint256;

    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "SafeERC20: TRANSFER_FAILED"
        );
    }

    // function safeTransfer(IERC20 token, address to, uint256 value) internal {
    //     callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    // }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeERC20: decreased allowance below zero"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length
        require(
            address(token).isContractt(),
            "SafeERC20: call to non-contract"
        );

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

contract FireFlyRouter is Ownable {
    using SafeERC20 for IERC20;
    using SignatureCheckerLib for address;
    using TrustlessPermit for address;

    error AmountError();
    error CallError();

    event Deposit();
    event Withdraw();

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

    constructor(address _owner, address _router, address _permit2) {
        _initializeOwner(_owner);
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

    function deposit(address token, address target, uint256 amount) external payable {
        if (token == address(0)) {
            if (msg.value != amount) {
                revert AmountError();
            }
            (bool ok, ) = target.call{value: amount}("");
            if (!ok) {
                revert CallError();
            }
        } else {
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= amount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        emit Deposit();
    }

    function depositAndMulticall(
        address[] calldata tokens,
        uint256[] calldata amounts,
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        // Transfer the tokens to the router
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, router, amounts[i]);
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
        emit Deposit();
    }

    function withdraw(address token, address target, uint256 amount) external payable {
        if (token == address(0)) {
            if (msg.value != amount) {
                revert AmountError();
            }
            (bool ok, ) = target.call{value: amount}("");
            if (!ok) {
                revert CallError();
            }
        } else {
            uint256 allowance = IERC20(token).allowance(
                msg.sender,
                address(this)
            );
            require(allowance >= amount, "Token allowance too low");
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        emit Withdraw();
    }

    function withdrawAndMulticall(
        address[] calldata tokens,
        uint256[] calldata amounts,
        Call3Value[] calldata calls,
        address refundTo,
        address nftRecipient
    ) external payable returns (Result[] memory returnData) {
        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        // Revert if refundTo is zero address
        if (refundTo == address(0)) {
            revert RefundToCannotBeZeroAddress();
        }

        // Transfer the tokens to the router
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, router, amounts[i]);
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        returnData = IFireFlyCaller(router).multicall{value: msg.value}(
            calls,
            refundTo,
            nftRecipient
        );
        emit Deposit();
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
