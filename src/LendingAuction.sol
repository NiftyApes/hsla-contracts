pragma solidity ^0.8.2;
//SPDX-License-Identifier: MIT

import "./test/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LendingAuction {
    // Solidity 0.8.x provides safe math, but uses an invalid opcode error which comsumes all gas. SafeMath uses revert which returns all gas.
    using SafeMath for uint256;

    // ---------- STRUCTS --------------- //

    struct LoanAuction {
        // Current bestBidder
        address bestBidder;
        // NFT owner
        address nftOwner;
        // ask loan amount
        uint256 askLoanAmount;
        // ask interest rate
        uint256 askInterestRate;
        // ask duration of loan in number of seconds
        uint256 askLoanDuration;
        // best bid loan amount. includes accumulated interest in an active loan.
        uint256 bestBidLoanAmount;
        // best bid interest rate
        uint256 bestBidInterestRate;
        // best bid duration of loan in number of seconds
        uint256 bestBidLoanDuration;
        // timestamp of bestBid
        uint256 bestBidTime;
        // timestamp of loan execution
        uint256 loanExecutedTime;
        // timestamp of loanAuction completion. loanStartTime + bestBidLoanDuration
        uint256 loanEndTime;
        // Cumulative interest of varying rates paid by new bestBiddeers to buy out the loan auction
        uint256 historicInterest;
        // amount withdrawn by the nftOwner. This is the amount they will pay interest on, with askLoanAmount as minimum.
        uint256 loanAmountDrawn;
    }

    // ---------- STATE VARIABLES --------------- //

    // Mapping of nftId to nftContractAddress to LoanAuction struct
    mapping(address => mapping(uint256 => LoanAuction)) public loanAuctions;

    // ---------- EVENTS --------------- //

    // New Best Bid event
    event NewBestBid(
        address _bestBidder,
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _bestBidLoanAmount,
        uint256 _bestBidInterestRate,
        uint256 _bestBidLoanDuration
    );

    event BestBidWithdrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event NewAsk(
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _askLoanAmount,
        uint256 _askInterestRate,
        uint256 _askLoanDuration
    );

    event AskWithdrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event LoanExecuted(
        address _bestBidder,
        address _nftOwner,
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _bestBidLoanAmount,
        uint256 _bestBidInterestRate,
        uint256 _bestBidLoanDuration
    );

    event LoanDrawn(
        address indexed _nftContractAddress,
        uint256 indexed _nftId,
        uint256 _drawAmount,
        uint256 _totalDrawn
    );

    event LoanRepaidInFull(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    event AssetSeized(
        address indexed _nftContractAddress,
        uint256 indexed _nftId
    );

    // ---------- MODIFIERS --------------- //

    modifier isNFTOwner(address _nftContractAddress, uint256 _nftId) {
        _;
    }

    // ---------- FUNCTIONS -------------- //

    // cannot have some bid params better and some worse than ask.
    // when bidding on an executed loan need to work out if new bid extends loanDuration or restarts.
    function bid(
        address _nftContractAddress,
        uint256 _nftId,
        // will want this parameter for stable coins
        // uint256 _bidLoanAmount,
        uint256 _bidInterestRate,
        uint256 _bidLoanDuration
    ) public payable {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // if no bids or asks have ever been placed and loan not executed
        if (
            loanAuction.loanExecutedTime == 0 &&
            loanAuction.bestBidder ==
            0x0000000000000000000000000000000000000000 &&
            loanAuction.askLoanAmount == 0
        ) {
            console.log("newBestBid 1");

            // update best bid in LoanAuction Struct
            loanAuction.bestBidder = msg.sender;
            loanAuction.bestBidLoanAmount = msg.value;
            loanAuction.bestBidInterestRate = _bidInterestRate;
            loanAuction.bestBidLoanDuration = _bidLoanDuration;
            loanAuction.bestBidTime = block.timestamp;
        }
        // if bestBidder exists, no ask, and loan is not executed.
        else if (
            loanAuction.loanExecutedTime == 0 &&
            loanAuction.bestBidder !=
            0x0000000000000000000000000000000000000000 &&
            loanAuction.askLoanAmount == 0
        ) {
            console.log("newBestBid 2");

            uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
                _nftContractAddress,
                _nftId,
                block.timestamp
            );

            // Temporarily save current loan value and best bidder
            // uint256 currentLoanValue = loanAuction.bestBidLoanAmount + historicInterest + bestBidderInterest
            uint256 currentLoanValue = loanAuction.bestBidLoanAmount;
            address currentBestBidder = loanAuction.bestBidder;

            // Check that newly offered terms are better than current terms
            require(
                // Require bidAmount is greater than previous bid
                (msg.value > currentLoanValue &&
                    _bidInterestRate <= loanAuction.bestBidInterestRate &&
                    _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                    // OR
                    // Require interestRate is lower than previous bid
                    (msg.value >= currentLoanValue &&
                        _bidInterestRate < loanAuction.bestBidInterestRate &&
                        _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                    // OR
                    // Require loanDuration to be greater than previous bid
                    (msg.value >= currentLoanValue &&
                        _bidInterestRate <= loanAuction.bestBidInterestRate &&
                        _bidLoanDuration > loanAuction.bestBidLoanDuration),
                "Bid must have better terms than current best bid"
            );

            // update best bid in LoanAuction Struct
            loanAuction.bestBidder = msg.sender;
            loanAuction.bestBidLoanAmount = msg.value;
            loanAuction.bestBidInterestRate = _bidInterestRate;
            loanAuction.bestBidLoanDuration = _bidLoanDuration;
            loanAuction.historicInterest =
                loanAuction.historicInterest +
                bestBidderInterest;
            loanAuction.bestBidTime = block.timestamp;

            _buyOutBestBid(currentBestBidder, currentLoanValue);
        }
        // if no bestBidder exists, the bid is less than the ask parameters, and loan is not executed.
        else if (
            loanAuction.loanExecutedTime == 0 &&
            loanAuction.bestBidder ==
            0x0000000000000000000000000000000000000000 &&
            msg.value < loanAuction.askLoanAmount &&
            _bidInterestRate > loanAuction.askInterestRate &&
            _bidLoanDuration < loanAuction.askLoanDuration
        ) {
            console.log("newBestBid 2.5");

            // update best bid in LoanAuction Struct
            loanAuction.bestBidder = msg.sender;
            loanAuction.bestBidLoanAmount = msg.value;
            loanAuction.bestBidInterestRate = _bidInterestRate;
            loanAuction.bestBidLoanDuration = _bidLoanDuration;
            loanAuction.bestBidTime = block.timestamp;
        }
        //  this prevents bids from having some parameters that are worse than ask and some better
        // if there is a currentBestBid, bid is lower than ask, and loan is not executed.
        else if (
            loanAuction.loanExecutedTime == 0 &&
            loanAuction.bestBidder !=
            0x0000000000000000000000000000000000000000 &&
            msg.value < loanAuction.askLoanAmount &&
            _bidInterestRate > loanAuction.askInterestRate &&
            _bidLoanDuration < loanAuction.askLoanDuration
        ) {
            console.log("newBestBid 3");

            uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
                _nftContractAddress,
                _nftId,
                block.timestamp
            );

            // Temporarily save current loan value and best bidder
            // uint256 currentLoanValue = loanAuction.bestBidLoanAmount + historicInterest + bestBidderInterest
            uint256 currentLoanValue = loanAuction.bestBidLoanAmount;
            address currentBestBidder = loanAuction.bestBidder;

            // Check that newly offered terms are better than current terms
            require(
                // Require bidAmount is greater than previous bid
                (msg.value > currentLoanValue &&
                    _bidInterestRate <= loanAuction.bestBidInterestRate &&
                    _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                    // OR
                    // Require interestRate is lower than previous bid
                    (msg.value >= currentLoanValue &&
                        _bidInterestRate < loanAuction.bestBidInterestRate &&
                        _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                    // OR
                    // Require loanDuration to be greater than previous bid
                    (msg.value >= currentLoanValue &&
                        _bidInterestRate <= loanAuction.bestBidInterestRate &&
                        _bidLoanDuration > loanAuction.bestBidLoanDuration),
                "Bid must have better terms than current best bid"
            );

            // update best bid in LoanAuction Struct
            loanAuction.bestBidder = msg.sender;
            loanAuction.bestBidLoanAmount = msg.value;
            loanAuction.bestBidInterestRate = _bidInterestRate;
            loanAuction.bestBidLoanDuration = _bidLoanDuration;
            loanAuction.historicInterest =
                loanAuction.historicInterest +
                bestBidderInterest;
            loanAuction.bestBidTime = block.timestamp;

            _buyOutBestBid(currentBestBidder, currentLoanValue);
        }
        //if bestBid meets or exceeds ask parameters
        else if (
            msg.value >= loanAuction.askLoanAmount &&
            _bidInterestRate <= loanAuction.askInterestRate &&
            _bidLoanDuration >= loanAuction.askLoanDuration
        ) {
            // if a bestBidder does not exist and loan not currently executed
            if (
                loanAuction.loanExecutedTime == 0 &&
                loanAuction.bestBidder ==
                0x0000000000000000000000000000000000000000
            ) {
                console.log("newBestBid 4");

                // update best bid in LoanAuction Struct
                loanAuction.bestBidder = msg.sender;
                loanAuction.bestBidLoanAmount = msg.value;
                loanAuction.bestBidInterestRate = _bidInterestRate;
                loanAuction.bestBidLoanDuration = _bidLoanDuration;
                loanAuction.bestBidTime = block.timestamp;

                // set loan executed time
                loanAuction.loanExecutedTime = block.timestamp;
                // set loan end time
                loanAuction.loanEndTime =
                    loanAuction.loanExecutedTime +
                    loanAuction.bestBidLoanDuration;

                // emit loan executed event
                emit LoanExecuted(
                    loanAuction.bestBidder,
                    loanAuction.nftOwner,
                    _nftContractAddress,
                    _nftId,
                    loanAuction.bestBidLoanAmount,
                    loanAuction.bestBidInterestRate,
                    loanAuction.bestBidLoanDuration
                );
            }
            // if a bestBidder does exist and loan not currently executed
            else if (
                loanAuction.loanExecutedTime == 0 &&
                loanAuction.bestBidder !=
                0x0000000000000000000000000000000000000000
            ) {
                console.log("newBestBid 5");

                uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
                        _nftContractAddress,
                        _nftId,
                        block.timestamp
                    );

                // Temporarily save current loan value and best bidder
                // uint256 currentLoanValue = loanAuction.bestBidLoanAmount + historicInterest + bestBidderInterest
                uint256 currentLoanValue = loanAuction.bestBidLoanAmount;
                address currentBestBidder = loanAuction.bestBidder;

                // Check that newly offered terms are better than current terms
                require(
                    // Require bidAmount is greater than previous bid
                    (msg.value > currentLoanValue &&
                        _bidInterestRate <= loanAuction.bestBidInterestRate &&
                        _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                        // OR
                        // Require interestRate is lower than previous bid
                        (msg.value >= currentLoanValue &&
                            _bidInterestRate <
                            loanAuction.bestBidInterestRate &&
                            _bidLoanDuration >=
                            loanAuction.bestBidLoanDuration) ||
                        // OR
                        // Require loanDuration to be greater than previous bid
                        (msg.value >= currentLoanValue &&
                            _bidInterestRate <=
                            loanAuction.bestBidInterestRate &&
                            _bidLoanDuration > loanAuction.bestBidLoanDuration),
                    "Bid must have better terms than current best bid"
                );

                // update best bid in LoanAuction Struct
                loanAuction.bestBidder = msg.sender;
                loanAuction.bestBidLoanAmount = msg.value;
                loanAuction.bestBidInterestRate = _bidInterestRate;
                loanAuction.bestBidLoanDuration = _bidLoanDuration;
                loanAuction.historicInterest =
                    loanAuction.historicInterest +
                    bestBidderInterest;
                loanAuction.bestBidTime = block.timestamp;

                // set loan executed time
                loanAuction.loanExecutedTime = block.timestamp;

                // set loan end time
                loanAuction.loanEndTime =
                    loanAuction.loanExecutedTime +
                    loanAuction.bestBidLoanDuration;

                // buy out loan from current best bidder
                _buyOutBestBid(currentBestBidder, currentLoanValue);

                // emit loan executed event
                emit LoanExecuted(
                    loanAuction.bestBidder,
                    loanAuction.nftOwner,
                    _nftContractAddress,
                    _nftId,
                    loanAuction.bestBidLoanAmount,
                    loanAuction.bestBidInterestRate,
                    loanAuction.bestBidLoanDuration
                );
            }
            // if a bestBidder does exist and loan is executed
            else if (
                loanAuction.loanExecutedTime != 0 &&
                loanAuction.bestBidder !=
                0x0000000000000000000000000000000000000000
            ) {
                console.log("newBestBid 6");

                uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
                        _nftContractAddress,
                        _nftId,
                        block.timestamp
                    );

                // Temporarily save current loan value and best bidder
                // uint256 currentLoanValue = loanAuction.bestBidLoanAmount + historicInterest + bestBidderInterest
                uint256 currentLoanValue = loanAuction.bestBidLoanAmount;
                address currentBestBidder = loanAuction.bestBidder;

                // Check that newly offered terms are better than current terms
                require(
                    // Require bidAmount is greater than previous bid
                    (msg.value > currentLoanValue &&
                        _bidInterestRate <= loanAuction.bestBidInterestRate &&
                        _bidLoanDuration >= loanAuction.bestBidLoanDuration) ||
                        // OR
                        // Require interestRate is lower than previous bid
                        (msg.value >= currentLoanValue &&
                            _bidInterestRate <
                            loanAuction.bestBidInterestRate &&
                            _bidLoanDuration >=
                            loanAuction.bestBidLoanDuration) ||
                        // OR
                        // Require loanDuration to be greater than previous bid
                        (msg.value >= currentLoanValue &&
                            _bidInterestRate <=
                            loanAuction.bestBidInterestRate &&
                            _bidLoanDuration > loanAuction.bestBidLoanDuration),
                    "Bid must have better terms than current best bid"
                );

                // update best bid in LoanAuction Struct
                loanAuction.bestBidder = msg.sender;
                loanAuction.bestBidLoanAmount = msg.value;
                loanAuction.bestBidInterestRate = _bidInterestRate;
                loanAuction.bestBidLoanDuration = _bidLoanDuration;
                loanAuction.historicInterest =
                    loanAuction.historicInterest +
                    bestBidderInterest;
                loanAuction.bestBidTime = block.timestamp;

                // need to think about bids within current duration vs. extending duration
                // set loan end time
                loanAuction.loanEndTime =
                    loanAuction.loanExecutedTime +
                    loanAuction.bestBidLoanDuration;

                // buy out loan from current best bidder
                _buyOutBestBid(currentBestBidder, currentLoanValue);
            }
        }
        // emit new best bid event
        emit NewBestBid(
            loanAuction.bestBidder,
            _nftContractAddress,
            _nftId,
            loanAuction.bestBidLoanAmount,
            loanAuction.bestBidInterestRate,
            loanAuction.bestBidLoanDuration
        );
    }

    function withdrawBid(address _nftContractAddress, uint256 _nftId) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // Ensure msg.sender is the current best bidder
        require(
            msg.sender == loanAuction.bestBidder,
            "Msg.sender is not the currentBestBidder"
        );
        // Ensure that loan is not executed
        require(
            loanAuction.loanExecutedTime == 0,
            "Cannot withdraw bid in an active loan"
        );

        // temporarily save current bestBid loan amount and bestBidder
        uint256 currentBestBidLoanAmount = loanAuction.bestBidLoanAmount;
        address currentBestBidder = loanAuction.bestBidder;

        console.log("currentBestBidder", currentBestBidder);
        console.log("currentBestBidLoanAmount", currentBestBidLoanAmount);

        // reset bestBid in loanAuction
        loanAuction.bestBidder = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidLoanAmount = 0;
        loanAuction.bestBidInterestRate = 0;
        loanAuction.bestBidLoanDuration = 0;
        loanAuction.bestBidTime = 0;

        // could refactor into internal function
        (bool success, ) = currentBestBidder.call{
            value: currentBestBidLoanAmount
        }("");
        require(success, "Bid withdrawal failed");

        // emit BidWithdrawn event
        emit BestBidWithdrawn(_nftContractAddress, _nftId);
    }

    function ask(
        address _nftContractAddress,
        uint256 _nftId,
        uint256 _askLoanAmount,
        uint256 _askInterestRate,
        uint256 _askLoanDuration
    ) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // Require that loan in not active
        require(
            loanAuction.loanExecutedTime == 0,
            "Cannot create a new ask during an active loan"
        );
        // Require askLoanAmount and askLoanDuration are greater than 0
        require(_askLoanAmount != 0, "Ask loan amount must be greater than 0");
        require(
            _askLoanDuration != 0,
            "Ask loan duration must be greater than 0"
        );

        // get nft owner
        address _nftOwner = IERC721(_nftContractAddress).ownerOf(_nftId);

        // if loanAuction.nftOwner is not set and there is no previous ask
        if (
            loanAuction.nftOwner ==
            0x0000000000000000000000000000000000000000 &&
            loanAuction.askLoanAmount == 0
        ) {
            // Ensure msg.sender is the nftOwner
            require(msg.sender == _nftOwner, "Msg.sender is not the NFT owner");

            // set the nftOwner
            loanAuction.nftOwner = _nftOwner;

            // transferFrom NFT from nftOwner to contract
            IERC721(_nftContractAddress).transferFrom(
                _nftOwner,
                address(this),
                _nftId
            );
        }
        // else verify msg.sender is loanAuction.nftOwner
        else {
            // Ensure msg.sender is the current nftOwner
            require(
                msg.sender == loanAuction.nftOwner,
                "Msg.sender is not the NFT owner"
            );
        }

        // update ask in LoanAuction Struct
        loanAuction.askLoanAmount = _askLoanAmount;
        loanAuction.askInterestRate = _askInterestRate;
        loanAuction.askLoanDuration = _askLoanDuration;

        if (
            loanAuction.bestBidLoanAmount >= loanAuction.askLoanAmount &&
            loanAuction.bestBidInterestRate <= loanAuction.askInterestRate &&
            loanAuction.bestBidLoanDuration >= loanAuction.askLoanDuration
        ) {
            // set loan executed time
            loanAuction.loanExecutedTime = block.timestamp;

            // set loan end time
            loanAuction.loanEndTime =
                loanAuction.loanExecutedTime +
                loanAuction.bestBidLoanDuration;

            // emit loan executed event
            emit LoanExecuted(
                loanAuction.bestBidder,
                loanAuction.nftOwner,
                _nftContractAddress,
                _nftId,
                loanAuction.bestBidLoanAmount,
                loanAuction.bestBidInterestRate,
                loanAuction.bestBidLoanDuration
            );
        }

        emit NewAsk(
            _nftContractAddress,
            _nftId,
            loanAuction.askLoanAmount,
            loanAuction.askInterestRate,
            loanAuction.askLoanDuration
        );
    }

    function withdrawAsk(address _nftContractAddress, uint256 _nftId) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        console.log("LoanAuction", loanAuction.nftOwner);

        // get nft owner from loanAuction struct
        address _nftOwner = loanAuction.nftOwner;

        // Ensure msg.sender is the current nftOwner
        require(msg.sender == _nftOwner, "Msg.sender is not the NFT Owner");
        // Ensure that loan is not executed
        require(
            loanAuction.loanExecutedTime == 0,
            "Cannot withdraw bid from an active loan"
        );

        // reset ask in loanAuction struct
        loanAuction.askLoanAmount = 0;
        loanAuction.askInterestRate = 0;
        loanAuction.askLoanDuration = 0;
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;

        // could refactor into internal function
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            _nftOwner,
            _nftId
        );

        // emit AskWithdrawn event
        emit AskWithdrawn(_nftContractAddress, _nftId);
    }

    function drawLoan(
        address _nftContractAddress,
        uint256 _nftId,
        uint256 _drawAmount
    ) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // get nft owner
        address _nftOwner = IERC721(_nftContractAddress).ownerOf(_nftId);

        // Ensure that loan is active
        require(
            loanAuction.loanExecutedTime != 0,
            "Loan is not active. No funds to withdraw."
        );

        // if loanAuction.nftOwner is not set
        if (
            loanAuction.nftOwner == 0x0000000000000000000000000000000000000000
        ) {
            // Ensure msg.sender is the nftOwner on the nft contract
            require(msg.sender == _nftOwner, "Msg.sender is not the NFT owner");
        }
        // else verify msg.sender is loanAuction.nftOwner
        else {
            // Ensure msg.sender is the current nftOwner
            require(
                msg.sender == loanAuction.nftOwner,
                "Msg.sender is not the NFT owner"
            );
            // Set _nftOwner to loanAuction.nftOwner contract value
            _nftOwner = loanAuction.nftOwner;
        }
        // Ensure that _drawAmount does not exceed bestBidLoanAmount
        require(
            (_drawAmount + loanAuction.loanAmountDrawn) <=
                loanAuction.bestBidLoanAmount,
            "Total amount withdrawn must not exceed best bid loan amount"
        );
        // Ensure that totalDrawn is greater than or equal to askLoanAmount
        require(
            (_drawAmount + loanAuction.loanAmountDrawn) >=
                loanAuction.askLoanAmount,
            "Total amount withdrawn must meet or exceed ask loan amount"
        );

        // set loanAmountDrawn
        loanAuction.loanAmountDrawn = _drawAmount + loanAuction.loanAmountDrawn;

        (bool success, ) = _nftOwner.call{value: _drawAmount}("");
        require(success, "Loan withdrawal failed");

        emit LoanDrawn(
            _nftContractAddress,
            _nftId,
            _drawAmount,
            loanAuction.loanAmountDrawn
        );
    }

    function repayFullLoan(address _nftContractAddress, uint256 _nftId)
        public
        payable
    {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // get nft owner
        address _nftOwner = loanAuction.nftOwner;

        // temporarily save current bestBidder
        address currentBestBidder = loanAuction.bestBidder;

        // get required repayment
        uint256 fullRepayment = calculateFullRepayment(
            _nftContractAddress,
            _nftId
        );

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot repay loan that has not been executed"
        );
        // check that transaction covers the full value of the loan
        require(
            msg.value >= fullRepayment,
            "Must repay full amount of loan drawn plus interest. Account for additional time for interest."
        );

        // reset loanAuction
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        loanAuction.askLoanAmount = 0;
        loanAuction.askInterestRate = 0;
        loanAuction.askLoanDuration = 0;
        loanAuction.bestBidder = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidLoanAmount = 0;
        loanAuction.bestBidInterestRate = 0;
        loanAuction.bestBidLoanDuration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.loanEndTime = 0;
        loanAuction.loanAmountDrawn = 0;

        // transferFrom NFT from contract to nftOwner
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            _nftOwner,
            _nftId
        );

        // repay eth plus interest to lender
        (bool success, ) = currentBestBidder.call{value: msg.value}("");
        require(success, "Repay bestBidder failed");

        emit LoanRepaidInFull(_nftContractAddress, _nftId);
    }

    // allows anyone to seize an asset of a past due loan on behalf on the bestBidder
    function seizeAsset(address _nftContractAddress, uint256 _nftId) public {
        // Instantiate LoanAuction Struct
        LoanAuction storage loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        // temporarily save current bestBidder
        address currentBestBidder = loanAuction.bestBidder;

        // Require that loan has been executed
        require(
            loanAuction.loanExecutedTime != 0,
            "Cannot seize asset for loan that has not been executed"
        );
        // Require that loan has expired
        require(
            block.timestamp >= loanAuction.loanEndTime,
            "Cannot seize asset before the end of the loan"
        );

        // reset loanAuction
        loanAuction.nftOwner = 0x0000000000000000000000000000000000000000;
        loanAuction.askLoanAmount = 0;
        loanAuction.askInterestRate = 0;
        loanAuction.askLoanDuration = 0;
        loanAuction.bestBidder = 0x0000000000000000000000000000000000000000;
        loanAuction.bestBidLoanAmount = 0;
        loanAuction.bestBidInterestRate = 0;
        loanAuction.bestBidLoanDuration = 0;
        loanAuction.bestBidTime = 0;
        loanAuction.loanExecutedTime = 0;
        loanAuction.loanEndTime = 0;
        loanAuction.loanAmountDrawn = 0;

        // transferFrom NFT from contract to bestBidder
        IERC721(_nftContractAddress).transferFrom(
            address(this),
            currentBestBidder,
            _nftId
        );

        emit AssetSeized(_nftContractAddress, _nftId);
    }

    // can you create a contract the is 721 compliant so that LendingAuction are just an extension of existing 721 contracts?
    function ownerOf(address _nftContractAddress, uint256 _nftId)
        public
        view
        returns (address)
    {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        return loanAuction.nftOwner;
    }

    // since funds are transferred as soon as match happens but before draw down,
    // need to have case where interest is calculated by askLoanAmount.
    // returns the interest value earned by bestBidder on active loanAmountDrawn
    function calculateInterestAccruedByBestBidder(
        address _nftContractAddress,
        uint256 _nftId,
        uint256 _timeOfInterest
    ) public view returns (uint256) {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        uint256 _secondsAsBestBidder;

        // if bestBidtime is before loanExecutedTime
        if (loanAuction.bestBidTime < loanAuction.loanExecutedTime) {
            // calculate seconds as bestBidder
            _secondsAsBestBidder =
                _timeOfInterest -
                loanAuction.loanExecutedTime;
        }
        // if bestBidtime is on or after loanExecutedTime
        else if (loanAuction.bestBidTime >= loanAuction.loanExecutedTime) {
            _secondsAsBestBidder = _timeOfInterest - loanAuction.bestBidTime;
        }

        // Seconds that loan has been active
        uint256 _secondsSinceLoanExecution = block.timestamp -
            loanAuction.loanExecutedTime;
        // percent of total loan time as bestBid
        uint256 _percentOfLoanTimeAsBestBid = SafeMath.div(
            _secondsSinceLoanExecution,
            _secondsAsBestBidder
        );

        uint256 _percentOfValue;

        if (loanAuction.loanAmountDrawn == 0) {
            // percent of value of askLoanAmount earned
            _percentOfValue = SafeMath.mul(
                loanAuction.askLoanAmount,
                _percentOfLoanTimeAsBestBid
            );
        } else if (loanAuction.loanAmountDrawn != 0) {
            // percent of value of loanAmountDrawn earned
            _percentOfValue = SafeMath.mul(
                loanAuction.loanAmountDrawn,
                _percentOfLoanTimeAsBestBid
            );
        }

        // Interest rate
        uint256 _interestRate = SafeMath.div(
            loanAuction.bestBidInterestRate,
            100
        );
        // Calculate interest amount
        uint256 _interestAmount = SafeMath.mul(_interestRate, _percentOfValue);
        // return interest amount
        return _interestAmount;
    }

    // need to ensure that repayment calculates each of the interest amounts for each of the bestBidders and pays them out
    function calculateFullRepayment(address _nftContractAddress, uint256 _nftId)
        public
        view
        returns (uint256)
    {
        LoanAuction memory loanAuction = loanAuctions[_nftContractAddress][
            _nftId
        ];

        uint256 bestBidderInterest = calculateInterestAccruedByBestBidder(
            _nftContractAddress,
            _nftId,
            block.timestamp
        );

        return
            loanAuction.loanAmountDrawn +
            loanAuction.historicInterest +
            bestBidderInterest;
    }

    // Internal function that pays off the previous bestBidder.
    // Includes interest if loan is active.
    function _buyOutBestBid(address _prevBestBidder, uint256 _buyOutAmount)
        internal
    {
        // send buyOutAmount to previous bestBidder
        (bool success, ) = _prevBestBidder.call{value: _buyOutAmount}("");
        require(success, "Buy out failed.");
    }

    function _getNFTOwner(address _nftContractAddress, uint256 _nftId)
        public
        view
        returns (address _nftOwner)
    {
        console.log(IERC721(_nftContractAddress).ownerOf(_nftId));
        return IERC721(_nftContractAddress).ownerOf(_nftId);
    }

    // @notice By calling 'revert' in the fallback function, we prevent anyone
    //         from accidentally sending funds directly to this contract.
    // function() external payable {
    //     revert();
    // }
}
