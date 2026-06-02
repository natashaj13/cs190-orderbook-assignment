// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderbook} from "./IOrderbook.sol";

/// @dev Minimal ERC20 surface the orderbook needs. The provided `MockERC20`
///      implements all of these methods (plus `mint`).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title Orderbook (template)
/// @notice Skeleton to complete. The constructor, immutable
///         token wiring, and the two trivial getters are already done —
///         everything else reverts with `"NotImplemented"`.
///
///         You are free to add additional state, structs, errors, and
///         helper functions. The only hard constraints are:
///         (1) keep the `IOrderbook` ABI exactly as declared in the
///             interface (the grading harness depends on it), and
///         (2) keep `baseToken`/`quoteToken` as immutables set in the
///             constructor.
contract Orderbook is IOrderbook {
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;

    struct Order {
        uint256 id;
        address addr;
        Side side;
        uint256 price;
        uint256 amount;
        uint256 next;
        uint256 prev;
    }

    mapping(uint256 => Order) public orders;
    uint256 public numBuys;
    uint256 public numSells;
    uint256 public bestBuyId;
    uint256 public worstBuyId;
    uint256 public bestSellId;
    uint256 public worstSellId;
    uint256 private nextOrderId = 1;

    /// @dev Suggested events. These are a starting point — your
    ///      implementation may emit a different set, rename them, or omit
    ///      events entirely. Nothing in the grading harness depends on
    ///      these signatures.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        Side side,
        uint256 price,
        uint256 amount
    );
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 fillAmount,
        uint256 fillPrice
    );
    event OrderCleared();

    constructor(address _baseToken, address _quoteToken) {
        require(_baseToken != address(0), "baseToken=0");
        require(_quoteToken != address(0), "quoteToken=0");
        require(_baseToken != _quoteToken, "base==quote");
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function getQuoteToken() external view returns (address) {
        return address(quoteToken);
    }

    function placeLimitOrder(Side side, uint256 price, uint256 amount) external returns (uint256) {
        if (side == Side.BUY) {
            uint256 currSellId = bestSellId;

            while (amount > 0 && currSellId != 0 && price >= orders[currSellId].price) {
                uint256 fillAmount = amount < orders[currSellId].amount ? amount : orders[currSellId].amount;
                uint256 quoteAmount = (fillAmount * orders[currSellId].price) / 1e18;
                
                address seller = orders[currSellId].addr;
                require(quoteToken.transferFrom(msg.sender, seller, quoteAmount), "quote transfer failed");
                require(baseToken.transfer(msg.sender, fillAmount), "base transfer failed");

                amount -= fillAmount;
                orders[currSellId].amount -= fillAmount;

                if (orders[currSellId].amount <= 0) {
                    //pop from sell linked list
                    uint256 nextId = orders[currSellId].next;
                    bestSellId = nextId;

                    if (nextId != 0) {
                        orders[nextId].prev = 0;
                    } else {
                        worstSellId = 0;
                    }
                    numSells--;
                    currSellId = nextId;
                }
            }
            if (amount > 0) {
                //insert into buy linked list 
                require(quoteToken.transferFrom(msg.sender, address(this), (amount*price)/1e18), "quote transfer failed");
                uint256 curr = bestBuyId;
                uint prev = 0;
                uint256 orderId = nextOrderId++;

                while (curr != 0 && price <= orders[curr].price) {
                    prev = curr;
                    curr = orders[curr].next;
                }

                orders[orderId] = Order({
                    id: orderId, 
                    addr: msg.sender, 
                    side: Side.BUY, 
                    price: price, 
                    amount: amount, 
                    next: curr, 
                    prev: prev
                });

                //empty list
                if (prev == 0 && curr == 0) {
                    bestBuyId = orderId;
                    worstBuyId = orderId;
                }
                //front of list
                else if (prev == 0) {
                    bestBuyId = orderId;
                    orders[curr].prev = orderId;
                }
                //back of list
                else if (curr == 0) {
                    worstBuyId = orderId;
                    orders[prev].next = orderId;
                }
                //prev and curr exist
                else {
                    orders[curr].prev = orderId;
                    orders[prev].next = orderId;
                }
                numBuys++;
            }
        }
        else {
            uint256 currBuyId = bestBuyId;

            while (amount > 0 && currBuyId != 0 && price <= orders[currBuyId].price) {
                uint256 fillAmount = amount < orders[currBuyId].amount ? amount : orders[currBuyId].amount;
                uint256 quoteAmount = (fillAmount * orders[currBuyId].price) / 1e18;
                
                address buyer = orders[currBuyId].addr;
                require(quoteToken.transfer(msg.sender, quoteAmount), "quote transfer failed");
                require(baseToken.transferFrom(msg.sender, buyer, fillAmount), "base transfer failed");

                amount -= fillAmount;
                orders[currBuyId].amount -= fillAmount;

                if (orders[currBuyId].amount <= 0) {
                    //pop from buy linked list
                    uint256 nextId = orders[currBuyId].next;
                    bestBuyId = nextId;

                    if (nextId != 0) {
                        orders[nextId].prev = 0;
                    } else {
                        worstBuyId = 0;
                    }
                    numBuys--;
                    currBuyId = nextId;
                }
            }
            if (amount > 0) {
                //insert into sell linked list 
                require(baseToken.transferFrom(msg.sender, address(this), amount), "base transfer failed");
                uint256 curr = bestSellId;
                uint prev = 0;
                uint256 orderId = nextOrderId++;

                while (curr != 0 && price >= orders[curr].price) {
                    prev = curr;
                    curr = orders[curr].next;
                }

                orders[orderId] = Order({
                    id: orderId, 
                    addr: msg.sender, 
                    side: Side.SELL, 
                    price: price, 
                    amount: amount, 
                    next: curr, 
                    prev: prev
                });

                //empty list
                if (prev == 0 && curr == 0) {
                    bestSellId = orderId;
                    worstSellId = orderId;
                }
                //front of list
                else if (prev == 0) {
                    bestSellId = orderId;
                    orders[curr].prev = orderId;
                }
                //back of list
                else if (curr == 0) {
                    worstSellId = orderId;
                    orders[prev].next = orderId;
                }
                //prev and curr exist
                else {
                    orders[curr].prev = orderId;
                    orders[prev].next = orderId;
                }
                numSells++;
            }
        }
    }

    function placeMarketOrder(Side side, uint256 amount) external {
        if (side == Side.BUY) {
            uint256 currSellId = bestSellId;

            while (amount > 0 && currSellId != 0) {
                uint256 fillAmount = amount < orders[currSellId].amount ? amount : orders[currSellId].amount;
                uint256 quoteAmount = (fillAmount * orders[currSellId].price) / 1e18;
                
                address seller = orders[currSellId].addr;
                require(quoteToken.transferFrom(msg.sender, seller, quoteAmount), "quote transfer failed");
                require(baseToken.transfer(msg.sender, fillAmount), "base transfer failed");

                amount -= fillAmount;
                orders[currSellId].amount -= fillAmount;

                if (orders[currSellId].amount <= 0) {
                    //pop from sell linked list
                    uint256 nextId = orders[currSellId].next;
                    bestSellId = nextId;

                    if (nextId != 0) {
                        orders[nextId].prev = 0;
                    } else {
                        worstSellId = 0;
                    }
                    numSells--;
                    currSellId = nextId;
                }
            }
        }
        else {
            uint256 currBuyId = bestBuyId;
            while (amount > 0 && currBuyId != 0) {
                uint256 fillAmount = amount < orders[currBuyId].amount ? amount : orders[currBuyId].amount;
                uint256 quoteAmount = (fillAmount * orders[currBuyId].price) / 1e18;
                
                address buyer = orders[currBuyId].addr;
                require(quoteToken.transfer(msg.sender, quoteAmount), "quote transfer failed");
                require(baseToken.transferFrom(msg.sender, buyer, fillAmount), "base transfer failed");

                amount -= fillAmount;
                orders[currBuyId].amount -= fillAmount;

                if (orders[currBuyId].amount <= 0) {
                    //pop from buy linked list
                    uint256 nextId = orders[currBuyId].next;
                    bestBuyId = nextId;

                    if (nextId != 0) {
                        orders[nextId].prev = 0;
                    } else {
                        worstBuyId = 0;
                    }
                    numBuys--;
                    currBuyId = nextId;
                }
            }
        }
    }

    function clear() external {
        numBuys = 0;
        numSells = 0;
        bestBuyId = 0;
        worstBuyId = 0;
        bestSellId = 0;
        worstSellId = 0;
        nextOrderId = 1;
    }

    function getBidsCount() external view returns (uint256) {
        return numBuys;
    }

    function getAsksCount() external view returns (uint256) {
        return numSells;
    }

    function getMidPrice() external view returns (uint256) {
        if (bestBuyId == 0 || bestSellId == 0) {
            revert("No bids or asks");
        }
        uint256 bestBid = orders[bestBuyId].price;
        uint256 bestAsk = orders[bestSellId].price;
        return (bestBid + bestAsk) / 2;
    }
}
