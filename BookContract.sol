pragma solidity ^0.4.0;//version 0.4 or higher

contract BookContract{
    //participating entities with Ethereum addresses
    address publisher;
    address author; //book author
    string public bookDescription;//description of book
    enum contractState { NotReady,Created, VerifiedandWaitingforCustomer, Aborted}
    contractState public state; 
    enum customerState {lookingforBook, MoneyDeposited,  ReceivedBookHashandToken, DoneVerification, SuccessfulDownload, UnsuccessfulDownload,Dispute, MoneyRefundedFully, HalfofMoneyRefunded  }
  
    uint bookPrice;
    uint authorRoyalty;
    uint publisherRoyalty;
    uint authorPayment;
    uint publisherPayment;
    uint public numberOfSuccessfulSales; //number of successful sales that were able to download the file and deposited correct amount of money
    uint public numberOfCustomers;//total number of customers inclusing those who deposited the money but could not download the file
    string MD5BookHash;
    mapping (address => customerState) public customers;//every ethereum address points to the state of the customer
    mapping (address => bool) public customerDownloadResult;
    
    //constructor
        function BookContract(){
         bookDescription = "This book is a work of fiction.";
         bookPrice = 5 ether;//$13
         author = 0x583031d1113ad414f02576bd6afabfb302140225;
         publisher = msg.sender; //address of contract creater (publisher)
         authorRoyalty = 15;
         publisherRoyalty = 85;
         authorPayment = (authorRoyalty*bookPrice)/100;//15% of the bookPrice is to the author
         publisherPayment = (publisherRoyalty*bookPrice)/100;//85% of the bookPrice is to the publisher
         state = contractState.NotReady;
         numberOfSuccessfulSales = 0;
         numberOfCustomers = 0;
         MD5BookHash = "6121769d20dda4884aa247f2649b9d8f";//MD5 hash of the book
    }
    //modifiers
    modifier  OnlyPublisher(){
        require(msg.sender == publisher); 
        _;
    }
    modifier  NotPublisher(){
        require(msg.sender != publisher); 
        _;
    }
    
    
    modifier  OnlyAuthor(){
        require(msg.sender == author); 
        _;
    }
  modifier  NotAuthor(){
        require(msg.sender != author); 
        _;
    }
    modifier costs() 
    {
        require(msg.value == 2 * bookPrice);//depositing twice the book price
        _;
    }
    
    //Tracking Events
    event ContractCreated(address owner);//publisher announces contract is created
    event VerifiedContractSuccess(address author);//contract is verified and agreed with
    event ContractAborted(address receiver);//no agreement on contract content
    event DepositMoneyDone(address customer, string info);
    event HashProvidedToCustomer(address publisher, string info, address customer);
    event MD5HashANDTokenProvidedToCustomer(address publisher, string info, string hash, string info2,  bytes32 token ,address customer);
    event DownloadSuccess(address customer, string info);
    event DownloadFailure(address customer, string info);
    event PaymentSettled(address customer, string info);
    event CustomerRefundFully(address customer, string info);
    event CustomerRefundHalfTheAmount(address customer, string info);
    event DownloadVerificationDispute(address publisher, address customer, string info);
    event HashVerifiedByCustomer(address customer, string info, bool result);
    
    function CreateAgreementContract() OnlyPublisher {
        require(state == contractState.NotReady);
            state = contractState.Created;
            ContractCreated(msg.sender); //trigger event
    }
    
    function DepositEtherToBuyBook() payable costs NotAuthor NotPublisher {
        require(state == contractState.VerifiedandWaitingforCustomer && 
        customers[msg.sender] == customerState.lookingforBook );
        customers[msg.sender] = customerState.MoneyDeposited;
        DepositMoneyDone(msg.sender, "Money Deposited , Customer Waiting for Token And Hash"); //trigger event
            
    }
    function provideHashANDToken(address customerAddress) OnlyPublisher ()
    {
        require(customers[customerAddress] == customerState.MoneyDeposited);
        //generate unique Token
        bytes32 token = keccak256(msg.sender, numberOfCustomers, numberOfSuccessfulSales, block.timestamp);
        customers[customerAddress] = customerState.ReceivedBookHashandToken;
        MD5HashANDTokenProvidedToCustomer(msg.sender,  "Hash" , MD5BookHash, "Token", token, customerAddress);
   }
    //customer verifies the hash and posts the result
    function verifyHash(address customerAddress, bool result)  NotAuthor NotPublisher
    {
        require(customers[customerAddress] == customerState.ReceivedBookHashandToken);
        customers[customerAddress] = customerState.DoneVerification;
        customerDownloadResult[customerAddress] = result; //save the download result of the customer
        HashVerifiedByCustomer(msg.sender, "Hash verified by the customer as " , result);
    }
    //publisher verifies downlaod
    function verifyDownload(address customerAddress , bool result) OnlyPublisher{
        require(customers[customerAddress] == customerState.DoneVerification);
        numberOfCustomers += 1;
        if (customerDownloadResult[customerAddress])//both are true or customer=true, publisher=false
        {
           DownloadSuccess(msg.sender, "Hash verified, and download is successful by the customer ") ;
           customers[customerAddress] = customerState.SuccessfulDownload;
           numberOfSuccessfulSales += 1;
           settlePayment(customerAddress,  true);
           PaymentSettled(msg.sender, "All parties received their payment of a successful transaction.");
          
        }
        else if(customerDownloadResult[customerAddress] == false && result == false){//no download 
            DownloadFailure(msg.sender, "UnsuccessfulDownload/Hash Mismatch by the customer ");
            customers[customerAddress] = customerState.UnsuccessfulDownload;
            settlePayment(customerAddress, false);
            CustomerRefundFully(msg.sender, "Customer is refunded due to an Unsuccessful transaction.");
        }
        else if (customerDownloadResult[customerAddress] == false && result == true){//dispute, solved offchain
            DownloadVerificationDispute(msg.sender, customerAddress, "Dispute should be solved off the chain");
            customers[customerAddress] = customerState.Dispute;
            settlePayment(customerAddress, true);
            CustomerRefundHalfTheAmount(msg.sender, "There is a dispute. Customer is refunded half of the money only.");
        }
    }
    
    //can only be called from within the contract
    function settlePayment(address customerAddress, bool result) internal {
        if(result){
            require(customers[customerAddress] == customerState.SuccessfulDownload || customers[customerAddress] == customerState.Dispute );
            customerAddress.transfer(bookPrice); //return half of what was initially paid to the customerAddress
            publisher.transfer(publisherPayment);
            author.transfer(authorPayment);
        }else {
            require(customers[customerAddress] == customerState.UnsuccessfulDownload);
            customerAddress.transfer(2*bookPrice);//return full amount paid by customer 
        }
    }
    function VerifyContract(bool result) OnlyAuthor {
        require(state == contractState.Created);
        if(result == true){//agreed upon and waiting for customers
            state = contractState.VerifiedandWaitingforCustomer;
            VerifiedContractSuccess(msg.sender);
        }
        else if (result == false){//no agreement on contract conditions
            state = contractState.Aborted;
            ContractAborted(msg.sender);
            selfdestruct(msg.sender);
        }
    }
    
    
 
    
}   
