// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/ModelInterface.sol";
import "../ModelStorage.sol";
import "../3rdDeFiInterfaces/CTokenInterface.sol";
import "../3rdDeFiInterfaces/IUniswapV2Router.sol";
import "../3rdDeFiInterfaces/IComptroller.sol";

contract WbtcModel is ModelInterface, ModelStorage {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Swap(uint256 compAmount, uint256 underlying);

    address _cToken;
    address _comp;
    address _comptroller;
    address _uRouterV2;
    uint256 public leverage;

    IComptroller public Comptroller;

    function initialize(
        address forge_,
        address token_,
        address cToken_,
        address comp_,
        address comptroller_,
        address uRouterV2_
    ) public {
        addToken(token_);
        setForge(forge_);
        _cToken = cToken_;
        _comp = comp_;
        _comptroller = comptroller_;
        _uRouterV2 = uRouterV2_;
        Comptroller = IComptroller(_comptroller);

        leverage = 30;
    }

    function underlyingBalanceInModel() public view override returns (uint256) {
        return IERC20(token(0)).balanceOf(address(this));
    }

    function underlyingBalanceWithInvestment() public view override returns (uint256) {
        // Hard Work Now! For Punkers by 0xViktor
        return
            underlyingBalanceInModel().add(
                CTokenInterface(_cToken).exchangeRateStored().mul(_cTokenBalanceOf()).div(1e18)
            );
    }

    function invest() public override {
        // Hard Work Now! For Punkers by 0xViktor
        IERC20(token(0)).safeApprove(_cToken, underlyingBalanceInModel());

        emit Invest(underlyingBalanceInModel(), block.timestamp);
        CTokenInterface(_cToken).mint(underlyingBalanceInModel());
        _borrow();
    }

    function reInvest() public {
        // Hard Work Now! For Punkers by 0xViktor
        _claimComp();
        _swapCompToUnderlying();
        invest();
    }

    function withdrawAllToForge() public override OnlyForge {
        // Hard Work Now! For Punkers by 0xViktor
        _claimComp();
        _swapCompToUnderlying();
        _repay(CTokenInterface(_cToken).balanceOfUnderlying(address(this)).mul(leverage).div(100));

        emit Withdraw(underlyingBalanceWithInvestment(), forge(), block.timestamp);
        CTokenInterface(_cToken).redeem(_cTokenBalanceOf());
    }

    function withdrawToForge(uint256 amount) public override OnlyForge {
        withdrawTo(amount, forge());
    }

    function withdrawTo(uint256 amount, address to) public override OnlyForge {
        // Hard Work Now! For Punkers by 0xViktor
        _repay(amount.mul(leverage).div(100));
        uint256 oldBalance = IERC20(token(0)).balanceOf(address(this));
        amount = Math.min(amount, CTokenInterface(_cToken).balanceOfUnderlying(address(this)));
        amount = CTokenInterface(_cToken).redeemUnderlying(amount);
        uint256 newBalance = IERC20(token(0)).balanceOf(address(this));
        require(newBalance.sub(oldBalance) > 0, "MODEL : REDEEM BALANCE IS ZERO");
        IERC20(token(0)).safeTransfer(to, newBalance.sub(oldBalance));

        emit Withdraw(amount, forge(), block.timestamp);
    }

    function setLeveragePercent(uint256 _leveragePercent) external OnlyForge {
        leverage = _leveragePercent;
        _borrow();
    }

    function _borrow() internal {
        uint256 borrowBalance = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
        uint256 availableCollateral = CTokenInterface(_cToken).balanceOfUnderlying(address(this)).sub(borrowBalance);
        uint256 canBorrowAmount = availableCollateral.mul(leverage).div(100);

        if (borrowBalance > canBorrowAmount) {
            _repay(borrowBalance.sub(canBorrowAmount));
            return;
        }

        uint256 toBorrow = canBorrowAmount.sub(borrowBalance);
        CTokenInterface(_cToken).borrow(toBorrow);
        CTokenInterface(_cToken).mint(toBorrow);
    }

    function _repay(uint256 _amount) internal {
        _amount = Math.min(_amount, CTokenInterface(_cToken).borrowBalanceCurrent(address(this)));
        CTokenInterface(_cToken).redeemUnderlying(_amount);
        CTokenInterface(_cToken).repayBorrow(_amount);
    }

    function _cTokenBalanceOf() internal view returns (uint256) {
        return CTokenInterface(_cToken).balanceOf(address(this));
    }

    function _claimComp() internal {
        // Hard Work Now! For Punkers by 0xViktor
        CTokenInterface(_comptroller).claimComp(address(this));
    }

    function _swapCompToUnderlying() internal {
        // Hard Work Now! For Punkers by 0xViktor
        uint256 balance = IERC20(_comp).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_comp).safeApprove(_uRouterV2, balance);

            address[] memory path = new address[](3);
            path[0] = address(_comp);
            path[1] = IUniswapV2Router02(_uRouterV2).WETH();
            path[2] = address(token(0));

            IUniswapV2Router02(_uRouterV2).swapExactTokensForTokens(
                balance,
                1,
                path,
                address(this),
                block.timestamp + (15 * 60)
            );

            emit Swap(balance, underlyingBalanceInModel());
        }
    }
}
