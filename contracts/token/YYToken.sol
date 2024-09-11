// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../interface/IERC20.sol";

contract YYToken is IERC20,IERC20Errors {
    string private _name;
    string private _symbol;
    uint8 private _decimals;//代币精度
    uint256 private _totalSupply;
    mapping(address=>uint256) private _balances;//账本
    mapping(address=>mapping (address => uint256)) private _allowances;//授权记录
    address public owner;//合约发布者
    
    constructor(string memory _initName,string memory _initSymbol,uint8 _initDecimals,uint256 _initTotalSupply) {
        _name=_initName;
        _symbol=_initSymbol;
        _decimals=_initDecimals;
        _totalSupply=_initTotalSupply;
        owner=msg.sender;
        //合约部署时把所有的代币发行给合约发布者
        _balances[owner]=_initTotalSupply;
    }

    function name() external view override returns(string memory){
        return _name;
    }

    function symbol() external view override returns(string memory){
        return _symbol;
    }

    function decimals() external view override returns(uint8){
        return _decimals;
    }

    function totalSupply() external view override returns(uint256){
        return _totalSupply;
    }

    function balanceOf(address _owner) external view override returns(uint256){
        return _balances[_owner];
    }

    function transfer(address _to,uint256 _value) external override returns(bool success_){
        if(_balances[msg.sender]<_value){
            revert ERC20InsufficientBalance(msg.sender, _balances[msg.sender], _value);
        }
        if(_to==address(0)){
            revert ERC20InvalidReceiver(address(0));
        }
        unchecked {
            // Overflow not possible: value <= fromBalance <= totalSupply.
            _balances[msg.sender] -= _value;
            _balances[_to]+=_value;
        }
        emit Transfer(msg.sender,_to,_value);
        success_=true;
    }

    function approve(address _spender,uint256 _value) external override returns(bool success_){
        if(_spender==address(0)){
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[msg.sender][_spender]=_value;
        emit Approval(msg.sender,_spender,_value);
        success_=true;
    }

    function allowance(address _owner,address _spender) external view override returns(uint256 remaining_){
        return _allowances[_owner][_spender];
    }

    function transferFrom(address _from,address _to,uint256 _value) external override returns(bool success_){
        if(_balances[_from]<_value){
            revert ERC20InsufficientBalance(_from, _balances[_from], _value);
        }
        if(_allowances[_from][msg.sender]<_value){
            revert ERC20InsufficientAllowance(_from, _allowances[_from][msg.sender], _value);
        }
        _balances[_from]-=_value;
        _balances[_to]+=_value;
        _allowances[_from][msg.sender]-=_value;
        emit Transfer(_from,_to,_value);
        success_=true;
    }
}