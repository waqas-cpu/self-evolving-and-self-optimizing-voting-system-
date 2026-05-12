// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataBuffer} from "../../contracts/l4/DataBuffer.sol";

interface Vm {
    function warp(uint256 ts) external;
}

contract DataBufferTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testCommitRevealConsume() public {
        address owner = address(this);
        DataBuffer buf = new DataBuffer(owner);
        bytes32 batch = keccak256("batch-a");
        bytes32 root = keccak256("root");
        buf.commit(batch, root, 3);
        (,, uint256 revealAt,,, bool revealed,) = buf.getBatch(batch);
        require(!revealed, "not revealed yet");
        require(revealAt > block.timestamp, "reveal in future");

        vm.warp(revealAt + 1);
        buf.reveal(batch);
        require(buf.isRevealed(batch), "revealed");
        require(buf.getMerkleRoot(batch) == root, "root");

        buf.consume(batch);
        require(buf.isConsumed(batch), "consumed");
    }

    function testCannotConsumeBeforeReveal() public {
        DataBuffer buf = new DataBuffer(address(this));
        bytes32 batch = keccak256("b2");
        buf.commit(batch, keccak256("r2"), 1);
        (bool ok,) = address(buf).call(abi.encodeCall(DataBuffer.consume, (batch)));
        require(!ok, "should revert");
    }
}
