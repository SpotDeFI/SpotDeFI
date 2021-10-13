// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract CDNote {
    
    constructor () {
    noteNumber = 1; //CD NOTE #
    DAO = msg.sender;
    fee = 5;// 10,000 = 100% 
    contractAddress = payable(address(this)); //Makes this contract payable
    blocksPerDay = 1;//5760 blocks per day
    timeLockMin = 2; // Days
    timeLockMax = 730; //Days
    loanTimeLimit = 2; //Days
    rateMax = 2000; //Days 
    maxBorrow = 2; // borrow have CD
    earlyBorrowWithdrawlFee = 50; // 10,000 = 100%
    minDeposit = 10000000000000; // 10,000 gwei min deposi
}
    address public DAO;
    address payable public contractAddress;
    uint256 public noteNumber;
    uint256 public fee;
    uint256 public earlyBorrowWithdrawlFee;
    uint256 public timeLockMin;
    uint256 public timeLockMax;
    uint256 public rateMax;
    uint256 public blocksPerDay;
    uint256 public maxBorrow;
    uint256 public loanTimeLimit;
    uint256 public minDeposit;
    bool public godSwitch; // protocol shutdown
    
modifier onlyDAO() {
    require(msg.sender == DAO, "Caller is not DAO Contract");
    _;
}
function changeBlkPerDay(uint256 _blocksPerDay) onlyDAO public {
    blocksPerDay = _blocksPerDay;
}
function changeFee(uint256 _fee) onlyDAO public {
    require(_fee <= 10000, '10,000 is 100%');
    fee = _fee;
}
function changeEarlyWithdrawlFee(uint256 _earlyBorrowWithdrawlFee) onlyDAO public {
    require(_earlyBorrowWithdrawlFee <= 10000, '10,000 is 100%');
    earlyBorrowWithdrawlFee = _earlyBorrowWithdrawlFee;
}
function changeOwner(address _DAO) onlyDAO public {
    DAO = _DAO;
}
function changeRateMax(uint256 _rateMax) onlyDAO public {
    require(_rateMax <= 10000, '10,000 is 100%');
    rateMax = _rateMax;
}
function changeTimeLockMax(uint256 _timeLockMax) onlyDAO public {
    require(_timeLockMax > timeLockMin);
    timeLockMax = _timeLockMax;
}
function changeTimeLockMin(uint256 _timeLockMin) onlyDAO public {
    require(_timeLockMin < timeLockMax);
    timeLockMin = _timeLockMin;
}
function contractBalance () view public returns(uint256){
return(address(this).balance);
}

function currentBlock () view public returns(uint256){
return(block.number);
}
function setGodSwitchON() onlyDAO public {
    godSwitch = true;
}
function setGodSwitchOFF() onlyDAO public {
    godSwitch = false;
}


struct depositNote   {
    uint256 noteNumber; //Note Number
    address accountAddress; //Account Address
    uint256 rate; //CD Rate
    uint256 fee; //CD Fee
    uint256 earlyBorrowWithdrawlFee; //Fee for early Withdraw
    uint256 block; //Deposit Block
    uint256 timeLock; //Number of Blocks the Deposit is locked up;
    uint256 ethBalance; //Balance of Eth in CD
    uint256 maturedValue; //Earned total value after timelock
    uint256 loanPay;
    uint256 loanBlockDue;
    bool valid; // Cd cleared, loaned, or expired on loan
    bool liquidated;
}

mapping (uint256 => depositNote) public cd;
mapping (address => uint256) public cdTracker;


event newCD (depositNote indexed);
event earlyWithdrawlCD (depositNote indexed);
event maturedCD (depositNote indexed);
event loanedCD (depositNote indexed);
event borrowCD (depositNote indexed);
event payLoan (depositNote indexed);
event liquidateCD (depositNote indexed, address indexed);
event transferAddress(depositNote indexed, address indexed);

//Deposit of Eth and ceation of CD note

function depositEth(uint256 _days) payable public {
    require (cdTracker[msg.sender] == 0, "Already Have Valid CD Note Use Another Address");
    uint256 _fee = calcFee(msg.value,fee);
    uint256 _earlyBorrowWithdrawlFee = calcFee(msg.value,earlyBorrowWithdrawlFee);
    require(msg.value >= minDeposit, "Min deposit not met");
    uint256 depositValue = msg.value - _fee;
    uint256 depositRate = rateCalc(_days);
    uint256 maturedValue = (((depositValue)*(depositRate))/10000) + depositValue;
    uint256 depositTimelock = _days * blocksPerDay;
    cd[noteNumber] = depositNote(noteNumber,msg.sender,depositRate,_fee,_earlyBorrowWithdrawlFee,block.number,depositTimelock,depositValue,maturedValue,0,0, true,false);
    cdTracker[msg.sender] = noteNumber;
    emit newCD (cd[noteNumber]);
    noteNumber = noteNumber +1;
} 

//Withdrawl of Matured CD Note @ end of timeLock

function withdrawlCD (uint256 _noteNumber ) payable public {
    require(godSwitch == false, "protocol shutdown");
    require(cd[_noteNumber].valid == true,  "Not a valid cd, loaned or cleared");
    require(cd[_noteNumber].accountAddress==msg.sender, "Not Note Owner");
    address _accountAddress = cd[_noteNumber].accountAddress;
    address payable _ethreceiver = payable(_accountAddress);
    uint256 cdMature = cd[_noteNumber].block + cd[_noteNumber].timeLock;
    require (cdMature <= block.number, "cd not matured");
    _ethreceiver.transfer(cd[_noteNumber].maturedValue);
    emit maturedCD(cd[_noteNumber]);
    cd[_noteNumber].valid = false;
    cd[_noteNumber].ethBalance = 0;
    cd[_noteNumber].maturedValue = 0;
    cdTracker[cd[_noteNumber].accountAddress] = 0;
}
function earlyWithdrawl (uint256 _noteNumber) payable public {
    require(godSwitch == false, "protocol shutdown");
    uint256 cdMature = cd[_noteNumber].block + cd[_noteNumber].timeLock;
    require (cdMature >= block.number, "use withdrawl CD");
    require(cd[_noteNumber].valid == true, "Not a valid cd, loaned or cleared");
    require(cd[_noteNumber].accountAddress==msg.sender, "Not Note Owner");
    address _accountAddress = cd[_noteNumber].accountAddress;
    address payable _ethreceiver = payable(_accountAddress);
    uint256 _value = cd[_noteNumber].ethBalance;
    _value = _value - cd[_noteNumber].earlyBorrowWithdrawlFee;
    _ethreceiver.transfer(_value);
    cd[_noteNumber].valid = false;
    cd[_noteNumber].ethBalance = 0;
    cd[_noteNumber].maturedValue = 0;
    cdTracker[cd[_noteNumber].accountAddress] = 0;
    emit earlyWithdrawlCD(cd[_noteNumber]);
} 
function borrowWithdrawl(uint256 _noteNumber, uint256 _value) payable public {
    require(godSwitch == false, "protocol shutdown");
    require(cd[_noteNumber].valid == true,  "Not a valid cd, loaned or cleared");
    require(cd[_noteNumber].accountAddress== msg.sender, "Not Note Owner");
    require((cd[_noteNumber].ethBalance - cd[_noteNumber].earlyBorrowWithdrawlFee )/ maxBorrow >= _value, "Over Borrow Limit");
    address _accountAddress = cd[_noteNumber].accountAddress;
    address payable _ethreceiver = payable(_accountAddress);
    cd[_noteNumber].ethBalance = cd[_noteNumber].ethBalance - cd[_noteNumber].earlyBorrowWithdrawlFee; 
    cd[_noteNumber].loanBlockDue = block.number + (loanTimeLimit * blocksPerDay);
    cd[_noteNumber].loanPay = _value; 
    _ethreceiver.transfer(_value);
    cd[_noteNumber].valid = false;
    emit borrowCD(cd[_noteNumber]);
}
function payLoanCD(uint256 _noteNumber)payable public{
    require(godSwitch == false, "protocol shutdown");
    require(cd[_noteNumber].valid == false, "CD has no loan");
    require(cd[_noteNumber].accountAddress==msg.sender, "Not Note Owner");
    require(cd[_noteNumber].loanBlockDue >= block.number, "Block Time Limit is Expired");
    require(msg.value >= cd[_noteNumber].loanPay, "More Value required" );
    cd[_noteNumber].loanPay = 0;
    cd[_noteNumber].loanBlockDue = 0;
    cd[_noteNumber].valid = true;
    emit payLoan(cd[_noteNumber]);
}
function liquidCD(uint256 _noteNumber)public {
    require(godSwitch == false, "protocol shutdown");
    require(cd[_noteNumber].valid == false , "CD not loaned");
    require(cd[_noteNumber].loanBlockDue <= block.number||cd[_noteNumber].timeLock <= block.number, "CD Matured while under Loan");
    cd[_noteNumber].valid = false;
    cd[_noteNumber].liquidated = true;
    cdTracker[cd[_noteNumber].accountAddress] = 0;
    emit liquidateCD(cd[_noteNumber], msg.sender);
}
function calcFee(uint256 _value, uint256 _fee) pure public returns(uint256){
    uint256 feeCalc = _value * _fee / 10000 ; 
    return(feeCalc);
}
function rateCalc(uint256 _days) view public returns(uint256){
    require(godSwitch == false, "protocol shutdown");
    require(timeLockMin <=_days, "Not enough days");
    require(timeLockMax >=_days, "too many days");
    uint256 slope = (rateMax)/timeLockMax;
    uint256 calcRate = _days * slope;
    return(calcRate);
}
function transferCD(uint256 _noteNumber, address _newAddress) public {
    require(godSwitch == false, "protocol shutdown");
    require(cd[_noteNumber].accountAddress==msg.sender, "Not Note Owner");
    require(cd[_noteNumber].loanBlockDue >= block.number, "Block Time Limit is Expired");
    require(cd[_noteNumber].valid == true,  "Not a valid cd, loaned or cleared");
    emit transferAddress(cd[noteNumber],_newAddress);
    cdTracker[cd[_noteNumber].accountAddress] = 0;
    cd[_noteNumber].accountAddress = _newAddress;
    cdTracker[_newAddress] = _noteNumber;
}
}
