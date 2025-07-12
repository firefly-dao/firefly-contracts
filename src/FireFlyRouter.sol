// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

contract FireFlyRouter {
    event Deposit(address from, uint256 chains, uint256 amount, address to);

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function deposit(uint256 chains, address to) external payable {
        require(msg.value != 0);
        emit Deposit(msg.sender, chains, msg.value, to);
    }

    function depositByCCTP(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        address targetContract
    ) external payable {
        IERC20(burnToken).transferFrom(msg.sender, address(this), amount); 
        IERC20(burnToken).approve(targetContract, amount);
        if (maxFee == 0) {
            ITokenMessengerV1(targetContract).depositForBurn(
                amount,
                destinationDomain,
                mintRecipient,
                burnToken
            );
        } else {
            ITokenMessengerV2(targetContract).depositForBurn(
                amount,
                destinationDomain,
                mintRecipient,
                burnToken,
                destinationCaller,
                maxFee,
                minFinalityThreshold
            );
        }
    }

    function withdraw(address token) external {
        require(msg.sender == owner);
        if (token == address(0)) {
            owner.call{value: address(this).balance}("");
        } else {
            IERC20(token).transfer(
                owner,
                IERC20(token).balanceOf(address(this))
            );
        }
    }

    function newOwner(address _owner) external {
        require(msg.sender == owner);
        owner = _owner;
    }
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

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
