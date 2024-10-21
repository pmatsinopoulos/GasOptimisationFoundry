// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";

error AdministratorAddressInvalid();
error AmountIsTooLow();
error AmountNotPositive();
error IdNotPositive();
error NotOwner();
error OriginatorNotSender();
error RecipientNameTooLong();
error SenderInsufficientBalance();
error TierLevelTooHigh();
error Unathorized();
error UserNotValidAddress();
error UserNotWhiteListed();
error UserTierIsIncorrect();

contract GasContract is Ownable {
    uint256 public immutable totalSupply; // cannot be updated
    uint256 public paymentCounter;
    mapping(address => uint256) public balances;
    uint256 public constant tradePercent = 12;
    address public contractOwner;
    bool public isReady = false;
    uint256 public tradeMode;
    mapping(address => Payment[]) public payments;
    mapping(address => uint256) public whitelist;
    address[5] public administrators;

    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }

    PaymentType constant defaultPayment = PaymentType.Unknown;

    History[] public paymentHistory; // when a payment was updated

    struct Payment {
        PaymentType paymentType;
        bool adminUpdated;
        uint256 paymentID;
        string recipientName; // max 8 characters
        address recipient;
        address admin; // administrators address
        uint256 amount;
    }

    struct History {
        uint256 lastUpdate;
        address updatedBy;
        uint256 blockNumber;
    }

    mapping(address => uint256) public isOddWhitelistUser;

    struct ImportantStruct {
        uint256 amount;
        uint256 valueA; // max 3 digits
        uint256 bigValue;
        uint256 valueB; // max 3 digits
        bool paymentStatus;
        address sender;
    }

    mapping(address => ImportantStruct) public whiteListStruct;

    event AddedToWhitelist(address userAddress, uint256 tier);

    event supplyChanged(address indexed, uint256 indexed);
    event Transfer(address recipient, uint256 amount);
    event PaymentUpdated(
        address admin,
        uint256 ID,
        uint256 amount,
        string recipient
    );
    event WhiteListTransfer(address indexed);

    constructor(address[] memory _admins, uint256 _totalSupply) {
        contractOwner = msg.sender;
        totalSupply = _totalSupply;

        // copy from _admins 5 elements and put them to administrators
        //
        for (uint256 ii = 0; ii < administrators.length; ii++) {
            administrators[ii] = _admins[ii];
        }

        balances[msg.sender] = _totalSupply;

        emit supplyChanged(msg.sender, _totalSupply);
    }

    function getPaymentHistory()
        public
        payable
        returns (
            // why turning this to +view+ it is more expensive?
            History[] memory paymentHistory_
        )
    {
        return paymentHistory;
    }

    function checkForAdmin(address _user) public view returns (bool admin_) {
        for (uint256 ii = 0; ii < administrators.length; ii++) {
            if (administrators[ii] == _user) {
                return true;
            }
        }
        return false;
    }

    function balanceOf(address _user) public view returns (uint256 balance_) {
        return balances[_user];
    }

    function addHistory(address _updateAddress) public {
        History memory history;
        history.blockNumber = block.number;
        history.lastUpdate = block.timestamp;
        history.updatedBy = _updateAddress;
        paymentHistory.push(history);
    }

    function getPayments(
        address _user
    ) public view returns (Payment[] memory payments_) {
        if (_user == address(0)) {
            revert UserNotValidAddress();
        }

        return payments[_user];
    }

    function transfer(
        address _recipient,
        uint256 _amount,
        string calldata _name
    ) public {
        if (balances[msg.sender] < _amount) {
            revert SenderInsufficientBalance();
        }

        if (bytes(_name).length >= 9) {
            revert RecipientNameTooLong();
        }

        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;

        Payment memory payment;

        payment.admin = address(0);
        payment.adminUpdated = false;
        payment.paymentType = PaymentType.BasicPayment;
        payment.recipient = _recipient;
        payment.amount = _amount;
        payment.recipientName = _name;
        payment.paymentID = ++paymentCounter;

        payments[msg.sender].push(payment);

        emit Transfer(_recipient, _amount);
    }

    function updatePayment(
        address _user,
        uint256 _ID,
        uint256 _amount,
        PaymentType _type
    ) public {
        onlyAdminOrOwner();

        if (_ID <= 0) {
            revert IdNotPositive();
        }

        if (_amount <= 0) {
            revert AmountNotPositive();
        }

        if (_user == address(0)) {
            revert AdministratorAddressInvalid();
        }

        for (uint256 ii = 0; ii < payments[_user].length; ii++) {
            if (payments[_user][ii].paymentID == _ID) {
                payments[_user][ii].adminUpdated = true;
                payments[_user][ii].admin = _user;
                payments[_user][ii].paymentType = _type;
                payments[_user][ii].amount = _amount;

                addHistory(_user);

                emit PaymentUpdated(
                    msg.sender,
                    _ID,
                    _amount,
                    payments[_user][ii].recipientName
                );

                break;
            }
        }
    }

    function addToWhitelist(address _userAddrs, uint256 _tier) public {
        onlyAdminOrOwner();

        if (_tier >= 255) {
            revert TierLevelTooHigh();
        }

        whitelist[_userAddrs] = _tier;

        if (_tier > 3) {
            whitelist[_userAddrs] = 3;
        } else if (_tier > 0) {
            whitelist[_userAddrs] = _tier;
        }

        isOddWhitelistUser[_userAddrs] = 1;

        emit AddedToWhitelist(_userAddrs, _tier);
    }

    function whiteTransfer(address _recipient, uint256 _amount) public {
        checkIfWhiteListed(msg.sender);

        address senderOfTx = msg.sender;
        whiteListStruct[senderOfTx] = ImportantStruct(
            _amount,
            0,
            0,
            0,
            true,
            msg.sender
        );

        if (balances[senderOfTx] < _amount) {
            revert SenderInsufficientBalance();
        }

        if (_amount <= 3) {
            revert AmountIsTooLow();
        }

        balances[senderOfTx] -= _amount;
        balances[_recipient] += _amount;
        balances[senderOfTx] += whitelist[senderOfTx];
        balances[_recipient] -= whitelist[senderOfTx];

        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(
        address sender
    ) public view returns (bool, uint256) {
        return (
            whiteListStruct[sender].paymentStatus,
            whiteListStruct[sender].amount
        );
    }

    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable {
        payable(msg.sender).transfer(msg.value);
    }

    // internal functions

    function onlyAdminOrOwner() internal view {
        address senderOfTx = msg.sender;
        if (!checkForAdmin(senderOfTx)) {
            revert Unathorized();
        }
        if (senderOfTx != contractOwner) {
            revert NotOwner();
        }
    }

    function checkIfWhiteListed(address sender) internal view {
        address senderOfTx = msg.sender;

        if (senderOfTx != sender) {
            revert OriginatorNotSender();
        }

        uint256 usersTier = whitelist[senderOfTx];

        if (usersTier <= 0) {
            revert UserNotWhiteListed();
        }

        if (usersTier >= 4) {
            revert UserTierIsIncorrect();
        }
    }
}
