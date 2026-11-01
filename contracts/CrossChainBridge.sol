// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ReentrancyGuard {
    bool private _nonReentrant;
    constructor() { _nonReentrant = false; }
    modifier nonReentrant() {
        require(!_nonReentrant, "ReentrancyGuard: reentrant call");
        _nonReentrant = true;
        _;
        _nonReentrant = false;
    }
}
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), _owner); }
    modifier onlyOwner() { require(_owner == msg.sender, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract CrossChainBridge is ReentrancyGuard, Ownable {
    struct Transfer {
        address sender;
        address recipient;
        uint256 amount;
        uint256 destinationChain;
        uint256 timestamp;
        bool completed;
    }
    Transfer[] public transfers;
    mapping(bytes32 => bool) public transferExists;
    uint256 public transferCount;
    uint256 public totalBridged;

    event TransferInitiated(uint256 indexed tid, address indexed sender, address indexed recipient, uint256 amount, uint256 destChain);
    event TransferCompleted(uint256 indexed tid, address indexed recipient, uint256 amount);

    function initiateTransfer(address recipient, uint256 amount, uint256 destinationChain)
        external payable nonReentrant returns (uint256) {
        require(amount > 0, "Zero amount");
        require(msg.value == amount, "Incorrect amount");
        require(destinationChain > 0, "Invalid chain");
        bytes32 id = keccak256(abi.encodePacked(msg.sender, recipient, amount, block.timestamp));
        require(!transferExists[id], "Duplicate transfer");
        Transfer storage t = transfers.push();
        t.sender = msg.sender;
        t.recipient = recipient;
        t.amount = amount;
        t.destinationChain = destinationChain;
        t.timestamp = block.timestamp;
        t.completed = false;
        uint256 tid = transfers.length - 1;
        transferCount = tid + 1;
        transferExists[id] = true;
        totalBridged += amount;
        emit TransferInitiated(tid, msg.sender, recipient, amount, destinationChain);
        return tid;
    }

    // FIX: completeTransfer now pays t.amount to t.recipient via call{value:}
    // instead of just flagging completed=true. Access opened to the recipient
    // (the party entitled to the bridged funds) so the pot is not a one-way lockbox.
    function completeTransfer(uint256 tid) external nonReentrant {
        Transfer storage t = transfers[tid];
        require(!t.completed, "Already completed");
        require(msg.sender == t.recipient, "Only recipient");
        t.completed = true;
        totalBridged -= t.amount;
        (bool ok,) = payable(t.recipient).call{value: t.amount}("");
        require(ok, "ETH transfer failed");
        emit TransferCompleted(tid, t.recipient, t.amount);
    }

    function getTransfer(uint256 tid) external view returns (address sender, address recipient, uint256 amount, uint256 destChain, uint256 timestamp, bool completed) {
        Transfer storage t = transfers[tid];
        return (t.sender, t.recipient, t.amount, t.destinationChain, t.timestamp, t.completed);
    }
}
