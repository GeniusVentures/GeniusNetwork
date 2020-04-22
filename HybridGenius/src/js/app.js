var BigNumber = require('bignumber.js');
App = {
  web3Provider: null,
  contracts: {},
  isAdmin: false,
  referral: "",
  isNewUser: true,

  init: function() {
    return App.initWeb3();
  },

  initWeb3: function() {
    // Initialize web3 and set the provider to the testRPC.
    // Modern dapp browsers...
    if(window.ethereum){
      App.web3Provider = window.ethereum; 
      window.web3 = new Web3(window.ethereum);
        try {
          // Request account access if needed
          // await ethereum.enable();
          window.ethereum.enable();

          // Acccounts now exposed
          // web3.eth.sendTransaction({/* ... */});
      } catch (error) {
          // User denied account access...
      }
    }
    // Legacy dapp browsers...
    else if (typeof web3 !== 'undefined') {
      App.web3Provider = web3.currentProvider;
      web3 = new Web3(web3.currentProvider);
      // Acccounts always exposed
      // web3.eth.sendTransaction({/* ... */});
    } else {
      // set the provider you want from Web3.providers
      App.web3Provider = new Web3.providers.HttpProvider('http://127.0.0.1:7545');
      web3 = new Web3(App.web3Provider);
    }

    return App.initContract();
  },

  initContract: function() {
    //parsing urls
    const queryString = window.location.search;
    const urlParams = new URLSearchParams(queryString);
    const referral = urlParams.get('referral')
    console.log("referral link is " + referral);
    $("#ReferralAddress").text(referral);
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      var base_url = "http://127.0.0.1:3000/?ref=";
      $(".MyReferralLink").text(base_url + account);
    });
    $.getJSON('HackbertToken.json', function(data) {
      // Get the necessary contract artifact file and instantiate it with truffle-contract.
      var HackbertTokenArtifact = data;
      App.contracts.HackbertToken = TruffleContract(HackbertTokenArtifact);

      // Set the provider for our contract.
      App.contracts.HackbertToken.setProvider(App.web3Provider);
      App.chechAddressIsOwnerOfHAC().then(function(result){
        if(result)
        {
          $('#admin-pannel').addClass("show");
          $('#admin-pannel').removeClass("hidden");
          
          $('#user-pannel').addClass("hidden");
          $('#user-pannel').removeClass("show");
          App.isAdmin = true;
        }
        else{
          $('#admin-pannel').addClass("hidden");
          $('#admin-pannel').removeClass("show");
          
          $('#user-pannel').addClass("show");
          $('#user-pannel').removeClass("hidden");
          App.isAdmin = false;
        }
      });
      // Use our contract to retieve and mark the adopted pets.
      App.getBalances().then(function(balance){
        $(".HACBalance").text(balance);
      });
    });
    $.getJSON('MainContract.json', function(data) {
      // Get the necessary contract artifact file and instantiate it with truffle-contract.
      var MaincontractArtifact = data;
      App.contracts.Maincontract = TruffleContract(MaincontractArtifact);

      // Set the provider for our contract.
      App.contracts.Maincontract.setProvider(App.web3Provider);
      App.chechAddressIsOwnerOfMainContract().then(function(result)
      {
        // Use our contract to retieve and mark the adopted pets.
        App.isAdmin = result;
        if(App.isAdmin){
          App.getTotalDepositedToken();
          App.getTotalUsers();
          App.getActivatedUsers();
          App.getMinimumDepositAmount();
          App.getMinimumWithdrawAmount();
          App.getActivationDays();
        }
        else{      //user side information
          App.isEntity().then((result)=>{
            App.isNewUser = !result;
            if(!App.isNewUser){
              App.getReferralAddress();
              App.getActivateState().then(function(result_value){
                if(result_value){
                  $('#ActiveState').text("YES");
                  App.getDepositedTokenOfUser().then(function(result){
                    $('#HACDeposited').text(result);
                  });
                }
                else{
                  $('#ActiveState').text("NO");
                  $('#HACDeposited').text("---");
                }
              });

            }
            else{
              $('#ActiveState').text("New User");
              $('#HACDeposited').text("---");
              $('#LastRewards').text("---");
            }
          })
        }
      });
    });
    return App.bindEvents();
  },

  bindEvents: function() {
    $(document).on('click', '#transferButton', App.handleTransfer);
    // //admin side
    $(document).on('click', '#ParamSetting', App.handleSetAdminParams);
    $(document).on('click', '#sendRewardsButton', App.handleDivideRewards);
    
    // //user side
    $(document).on('click', '#submitDeposit', App.handleSubmitDeposit);
    $(document).on('click', '#submitWithdraw', App.handleSubmitWithdraw);
    
    
  },
  chechAddressIsOwnerOfHAC: function(){ return new Promise((resolve,reject) => {
    console.log('Checking Address and decide admin or user ...');
    var hacbertTokenInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.HackbertToken.deployed().then(function(instance) {
        hacbertTokenInstance = instance;

        return hacbertTokenInstance.getOwner();
      }).then(function(result) {
        ownerAddress = result;
        resolve(ownerAddress == account);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},
  chechAddressIsOwnerOfMainContract: function(){ return new Promise((resolve,reject) => {
    console.log('Checking Address and decide admin or user ...');
    var MaincontractInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getOwner();
      }).then(function(result) {
        ownerAddress = result;
        resolve(ownerAddress == account);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},
  checkApprove: function(to,amount) { return new Promise((resolve,reject) => {
    console.log('Checking approve address ' + to + 'amount ' + amount +'...');
    var hacbertTokenInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.HackbertToken.deployed().then(function(instance) {
        hacbertTokenInstance = instance;

        return hacbertTokenInstance.approve(to,amount);
      }).then(function(result) {
        resolve(result);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},
  //user side java script
  
  //admin side java script
  handleSetAdminParams: function(event){
    event.preventDefault();
    var MinimumDepositAmount = parseFloat($('#MinimumDepositAmount').val());
    var MinimumWithdrawAmount = parseFloat($('#MinimumWithdrawAmount').val());
    var ActivationDays = parseInt($('#ActivationDays').val());
    App.setAdminParams(MinimumDepositAmount, MinimumWithdrawAmount, ActivationDays);
  },
  
  handleTransfer: function(event) {
    event.preventDefault();

    var amount = parseFloat($('#HACTransferAmount').val());
    var toAddress = $('#HACTransferAddress').val();

    console.log('Transfer ' + amount + ' HAC to ' + toAddress);

    var hacbertTokenInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.HackbertToken.deployed().then(function(instance) {
        hacbertTokenInstance = instance;

//        return hacbertTokenInstance.transferFrom(toAddress, amount, {from: account, gas: 100000});
        return hacbertTokenInstance.transferFrom(account, toAddress, amount,{ from: toAddress });
//        return instance.transfer(accounts[1], amount);

      }).then(function(result) {
        alert('Transfer Successful!');
        return App.getBalances();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },
  
  handleSubmitDeposit:function(event){
    event.preventDefault();
    var DepositAmount = parseFloat($('#HACDepositAmount').val());
    var _to = App.contracts.Maincontract.address;
    App.checkApprove(_to,HAC2WEI(DepositAmount)).then(function(result){
      if(result){
        App.placeDeposit(HAC2WEI(DepositAmount),App.referral).then(function(result2){
          if(result2){
            alert("place Deposit is Successfull");
          }
          else{
            alert("place Deposit is Fialed");
          }
          refreshPage();

        }).catch(function(err){
          console.log(err.message);
        });
      }
    })

  },

  handleSubmitWithdraw:function(event){
    event.preventDefault();
    var WithdrawAmount = parseFloat($('#HACWithdrawAmount').val());
    App.placeWithdraw(HAC2WEI(WithdrawAmount)).then(function(result){
      if(result){
        alert("place Withdraw is Successfull");
        refreshPage();
      }
      else{
        alert("place Withdraw is Failed");
      }
    }).catch(function(err){
      console.log(err.message);
    });
  },

  handleDivideRewards:function(event){
    event.preventDefault();
    var RewardsAmount = parseFloat($('#RewardsAmount').val());
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      let send = web3.eth.sendTransaction({
        from:account,
        to:App.contracts.Maincontract.address, 
        value:web3.toWei(RewardsAmount, "ether")
      },function(err,transactionHash){
        if (!err)
        console.log(transactionHash); 
      });
    });
  },
/////////////////////////////////////////////////////////////////////////         admin functions             ///////////////////////////////////////
  divideProfit: function(amount) { return new Promise((resolve, reject) => {
    console.log('dividing Profit...amount ' + amount);
    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.divideProfit(amount);
      }).then(function(result) {
        // balance = result.c[0];
        // balance = WEI2HAC(result);
        resolve(result);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},

  getBalances: function() { return new Promise((resolve, reject) => {
    console.log('Getting balances...');

    var hacbertTokenInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.HackbertToken.deployed().then(function(instance) {
        hacbertTokenInstance = instance;

        return hacbertTokenInstance.balanceOf(account);
      }).then(function(result) {
        // balance = result.c[0];
        balance = WEI2HAC(result);
        resolve(balance);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},


  getTotalDepositedToken: function() {
    console.log('Getting Total Deposited Tokens...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getTotalDepositedToken();
      }).then(function(result) {
        // balance = result.c[0];
        balance = WEI2HAC(result);
        $('#TotalDepsitedToken').text(balance);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getTotalUsers: function(){
    console.log('Getting Activated Users...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getTotalUsers();
      }).then(function(result) {
        returned_value = result.c[0];
        $('#TotalUsers').text(returned_value);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getActivatedUsers: function(){
    console.log('Getting Activated Users...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getActivatedUsers();
      }).then(function(result) {
        returned_value = result.c[0];
        $('#TotalActivatedUsers').text(returned_value);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getMinimumDepositAmount: function(){
    console.log('Getting MinimumDeposit Amount ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getMinimumDepositAmount();
      }).then(function(result) {
        // returned_value = result.c[0];
        returned_value = WEI2HAC(result);
        $('#MinimumDepositAmount').val(returned_value);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getMinimumWithdrawAmount: function(){
    console.log('Getting MinimumWithdraw Amount ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getMinimumWithdrawAmount();
      }).then(function(result) {
        // returned_value = result.c[0];
        returned_value = WEI2HAC(result);
        $('#MinimumWithdrawAmount').val(returned_value);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getActivationDays: function(){
    console.log('Getting Activation Days ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getActivationDays();
      }).then(function(result) {
        returned_value = result.c[0];
        $('#ActivationDays').val(returned_value);
        
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  setMinimumDepositAmount: function(_value) {
    console.log('Set Minimum Deposit Amount to  ' + _value + ' HAC ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;
        _value = HAC2WEI(_value);
        return MaincontractInstance.setMinimumDepositAmount(_value);
      }).then(function(result) {
        return App.getMinimumDepositAmount();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  setMinimumWithdrawAmount: function(_value) {
    console.log('Set Minimum Withdraw Amount to  ' + _value + ' HAC ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;
        _value = HAC2WEI(_value);
        return MaincontractInstance.setMinimumWithdrawAmount(_value);
      }).then(function(result) {
        return App.getMinimumWithdrawAmount();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  setActivationDays: function(_value) {
    console.log('Set Activation Days to  ' + _value + ' Days ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;
        return MaincontractInstance.setActivationDays(_value);
      }).then(function(result) {
        return App.getActivationDays();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  setAdminParams: function(minimumDepositAmount,minimumWithdrawAmount,activationDays) {
    console.log('Set Admin Params to minimumDepositAmount  ' +  minimumDepositAmount + 'HAC' +
                                  '  minimumWithdrawAmount  ' +  minimumWithdrawAmount + 'HAC' +
                                  '  activationDays  ' +  activationDays + ' Days ...');

    var MaincontractInstance;

    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;
        minimumDepositAmount = HAC2WEI(minimumDepositAmount);
        minimumWithdrawAmount = HAC2WEI(minimumWithdrawAmount);
        return MaincontractInstance.setAdminParams(minimumDepositAmount,minimumWithdrawAmount,activationDays);
      }).then(function(result) {
        App.getMinimumDepositAmount();
        App.getMinimumWithdrawAmount();
        App.getActivationDays();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },
  /////////////////////////////////////////////////////////////////////////         user functions             ///////////////////////////////////////
  getReferralAddress: function(){

    var MaincontractInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('Getting Referral Address of ' + account + '  .....');
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getReferralAddress(account);
      }).then(function(result) {
        returned_value = result;
        if(returned_value != "0x0000000000000000000000000000000000000000")
          $('#ReferralAddress').text(returned_value);
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  },


  getActivateState: function(){ return new Promise((resolve,reject) => {

    var MaincontractInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('Getting Referral Address of ' + account + '  .....');
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.getActivateState(account);
      }).then(function(result) {
        returned_value = result;
        resolve(returned_value);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},


  isEntity: function(){ return new Promise((resolve,reject) => {

    var MaincontractInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('checking is new user ' + account + '  .....');
      App.contracts.Maincontract.deployed().then(function(instance) {
        MaincontractInstance = instance;

        return MaincontractInstance.isEntity(account);
      }).then(function(result) {
        returned_value = result;
        resolve(returned_value);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},


  placeDeposit:function(amount,referral){ return new Promise((resolve, reject)=>{
    var MaincontractInstance;
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('place Depsoit  ' + amount + ' HAC,  referral ' + referral + '...');
      App.contracts.Maincontract.deployed().then(function(instance) {
        if(referral == null || referral == undefined)
          referral = "0x0000000000000000000000000000000000000000";
        return instance.placeDeposit(amount, referral);
      }).then(function(result) {
        resolve(result);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });}, 


  placeWithdraw:function(amount){ return new Promise((resolve, reject)=>{
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('place Depsoit  ' + amount + ' HAC...');
      App.contracts.Maincontract.deployed().then(function(instance) {
        return instance.placeWithdraw(amount);
      }).then(function(result) {
        resolve(result);
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });}, 

  getDepositedTokenOfUser:function(){return new Promise((resolve,reject) => {
    web3.eth.getAccounts(function(error, accounts) {
      if (error) {
        console.log(error);
      }
      var account = accounts[0];
      console.log('get Depsoited token od user address ' + account + '  ...');
      App.contracts.Maincontract.deployed().then(function(instance) {
        return instance.getDepositedTokenOfUser(account);
      }).then(function(result) {
        resolve(WEI2HAC(result));
      }).catch(function(err) {
        console.log(err.message);
        reject();
      });
    });
  });},
};

$(function() {
  $(window).load(function() {
    App.init();
  });
});
////////////////////////////////////////////////////////////////////////       general functions   ////////////////////////////////////////////////////
function HAC2WEI(_value){
  var amount = new BigNumber(_value);
  amount = web3.toWei(amount, "ether")
  return amount;
}
function WEI2HAC(_value){
  return _value.div(10**18).toFixed(3);
}
function refreshPage(){
  window.location.reload(true);
}