// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct Call3Value {
    address target;
    bool allowFailure;
    uint256 value;
    bytes callData;
}

struct Permit {
    address token;
    address owner;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct Result {
    bool success;
    bytes returnData;
}

struct FireFlyerWitness {
    address fireflyer;
    Call3Value[] call3Values;
}
