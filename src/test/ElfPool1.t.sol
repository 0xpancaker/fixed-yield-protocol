pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/ERC20.sol";
import "../interfaces/WETH.sol";

import "../libraries/SafeMath.sol";
import "../libraries/Address.sol";
import "../libraries/SafeERC20.sol";

import "../test/AYVault.sol";
import "../test/ALender.sol";

import "../test/AToken.sol";
import "../test/APriceOracle.sol";
import "../converter/ElementConverter.sol";

import "../assets/YdaiAsset.sol";
import "../assets/YtusdAsset.sol";
import "../assets/YusdcAsset.sol";
import "../assets/YusdtAsset.sol";
import "../pools/low/Elf.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract User {
    // max uint approve for spending
    function approve(address _token, address _guy) public {
        IERC20(_token).approve(_guy, uint256(-1));
    }

    // depositing WETH and minting
    function call_deposit(address payable _obj, uint256 _amount) public {
        Elf(_obj).deposit(_amount);
    }

    // deposit ETH, converting to WETH, and minting
    function call_depositETH(address payable _obj, uint256 _amount)
        public
        payable
    {
        Elf(_obj).depositETH{value: _amount}();
    }

    // withdraw specific shares to WETH
    function call_withdraw(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdraw(_amount);
    }

    // withdraw specific shares to ETH
    function call_withdrawETH(address payable _obj, uint256 _amount) public {
        Elf(_obj).withdrawETH(_amount);
    }

    // to be able to receive funds
    receive() external payable {}
}

contract ElfContractsTest is DSTest {
    Hevm hevm;
    WETH weth;

    Elf elf;
    ElfStrategy strategy;

    User user1;
    User user2;
    User user3;

    AToken dai;
    AToken tusd;
    AToken usdc;
    AToken usdt;

    AYVault ydai;
    AYVault ytusd;
    AYVault yusdc;
    AYVault yusdt;

    YdaiAsset ydaiAsset;
    YtusdAsset ytusdAsset;
    YusdcAsset yusdcAsset;
    YusdtAsset yusdtAsset;

    ElementConverter converter1;
    ALender lender1;
    APriceOracle priceOracle;

    // for testing a basic 4x25% asset percent split
    address[] fromTokens = new address[](4);
    address[] toTokens = new address[](4);
    uint256[] percents = new uint256[](4);
    address[] assets = new address[](4);
    uint256[] conversionType = new uint256[](4);

    function setUp() public {
        // hevm "cheatcode", see: https://github.com/dapphub/dapptools/tree/master/src/hevm#cheat-codes
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        weth = new WETH();

        // core element contracts
        elf = new Elf(address(weth));
        strategy = new ElfStrategy(address(elf), address(weth));
        converter1 = new ElementConverter(address(weth));

        // test lender implementation
        lender1 = new ALender(address(converter1), address(weth));
        // test price oracle implementation
        priceOracle = new APriceOracle();

        // the core contracts need to know the address of each downstream contract:
        // elf -> strategy
        // strategy -> converter, price oracle
        // converter -> lender
        elf.setStrategy(address(strategy));
        strategy.setConverter(address(converter1));
        strategy.setPriceOracle(address(priceOracle));
        converter1.setLender(address(lender1));

        // provide the test lender with a price oracle
        lender1.setPriceOracle(address(priceOracle));

        // 4 test token implementations
        dai = new AToken(address(lender1));
        tusd = new AToken(address(lender1));
        usdc = new AToken(address(lender1));
        usdt = new AToken(address(lender1));

        // 4 test vault implementations associated
        // with the 4 test token implementations
        ydai = new AYVault(address(dai));
        ytusd = new AYVault(address(tusd));
        yusdc = new AYVault(address(usdc));
        yusdt = new AYVault(address(usdt));

        // each asset represents a wrapper around an associated vault
        ydaiAsset = new YdaiAsset(address(strategy));
        ytusdAsset = new YtusdAsset(address(strategy));
        yusdcAsset = new YusdcAsset(address(strategy));
        yusdtAsset = new YusdtAsset(address(strategy));

        // this test requires that we override the hardcoded
        // vault and token addresses with test implementations
        ydaiAsset.setVault(address(ydai));
        ydaiAsset.setToken(address(dai));
        ytusdAsset.setVault(address(ytusd));
        ytusdAsset.setToken(address(tusd));
        yusdcAsset.setVault(address(yusdc));
        yusdcAsset.setToken(address(usdc));
        yusdtAsset.setVault(address(yusdt));
        yusdtAsset.setToken(address(usdt));

        // the following block of code initializes the allocations for this test
        uint256 numAllocations = uint256(4);
        fromTokens[0] = address(weth);
        fromTokens[1] = address(weth);
        fromTokens[2] = address(weth);
        fromTokens[3] = address(weth);
        toTokens[0] = address(dai);
        toTokens[1] = address(tusd);
        toTokens[2] = address(usdc);
        toTokens[3] = address(usdt);
        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);
        assets[0] = address(ydaiAsset);
        assets[1] = address(ytusdAsset);
        assets[2] = address(yusdcAsset);
        assets[3] = address(yusdtAsset);
        conversionType[0] = uint256(0);
        conversionType[1] = uint256(0);
        conversionType[2] = uint256(0);
        conversionType[3] = uint256(0);
        strategy.setAllocations(
            fromTokens,
            toTokens,
            percents,
            assets,
            conversionType,
            numAllocations
        );

        // create 3 users and provide funds
        user1 = new User();
        user2 = new User();
        user3 = new User();
        address(user1).transfer(1000 ether);
        address(user2).transfer(1000 ether);
        address(user3).transfer(1000 ether);
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user1), uint256(3))), // Mint user 1 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user2), uint256(3))), // Mint user 2 1000 WETH
            bytes32(uint256(1000 ether))
        );
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(user3), uint256(3))), // Mint user 3 1000 WETH
            bytes32(uint256(1000 ether))
        );
    }

    function test_correctUserBalances() public {
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_depositingETH() public {
        // deposit eth
        user1.call_depositETH(address(elf), 1 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);

        // verify that the dai asset and dai vault contain the expected balances
        uint256 expectedTokenBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedTokenBalance); // NOTE: dai to ydai is 1:1
        assertEq(IERC20(dai).balanceOf(address(ydai)), expectedTokenBalance);

        // verify that the tusd asset and tusd vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTokenBalance); // NOTE: tusd to ytusd is 1:1
        assertEq(IERC20(tusd).balanceOf(address(ytusd)), expectedTokenBalance);

        // verify that the usdc asset and usdc vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedTokenBalance); // NOTE: usdc to yusdc is 1:1
        assertEq(IERC20(usdc).balanceOf(address(yusdc)), expectedTokenBalance);

        // verify that the usdt asset and usdt vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedTokenBalance); // NOTE: usdt to yusdt is 1:1
        assertEq(IERC20(usdt).balanceOf(address(yusdt)), expectedTokenBalance);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);
        // verify that the balance calculation matches the deposited eth
        assertEq(elf.balance(), 1 ether);
    }

    function test_depositingWETH() public {
        // deposit eth
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);

        // verify that weth made it all the way to the lender
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);

        // verify that the dai asset and dai vault contain the expected balances
        uint256 expectedTokenBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedTokenBalance);

        // verify that the tusd asset and tusd vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTokenBalance);

        // verify that the usdc asset and usdc vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedTokenBalance);

        // verify that the usdt asset and usdt vault contain the expected balances
        expectedTokenBalance =
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedTokenBalance);

        // verify that the proper amount of elf was minted
        assertEq(elf.totalSupply(), 1 ether);
        // verify that the balance calculation matches the deposited eth
        assertEq(elf.balance(), 1 ether);
    }

    function test_multipleETHDeposits() public {
        // Deposit 1
        user1.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 1 ether);
        uint256 expectedDaiBalance = lender1.getLendingPrice(
            address(weth),
            address(dai)
        ) * 250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        uint256 expectedTusdBalance = lender1.getLendingPrice(
            address(weth),
            address(tusd)
        ) * 250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        uint256 expectedUsdcBalance = lender1.getLendingPrice(
            address(weth),
            address(usdc)
        ) * 250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        uint256 expectedUsdtBalance = lender1.getLendingPrice(
            address(weth),
            address(usdt)
        ) * 250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 2 ether);
        expectedDaiBalance +=
            lender1.getLendingPrice(address(weth), address(dai)) *
            250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        expectedTusdBalance +=
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        expectedUsdcBalance +=
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        expectedUsdtBalance +=
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // Deposit 3
        user3.call_depositETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(this)), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        expectedDaiBalance +=
            lender1.getLendingPrice(address(weth), address(dai)) *
            250 finney;
        assertEq(ydaiAsset.balance(), expectedDaiBalance);
        expectedTusdBalance +=
            lender1.getLendingPrice(address(weth), address(tusd)) *
            250 finney;
        assertEq(ytusdAsset.balance(), expectedTusdBalance);
        expectedUsdcBalance +=
            lender1.getLendingPrice(address(weth), address(usdc)) *
            250 finney;
        assertEq(yusdcAsset.balance(), expectedUsdcBalance);
        expectedUsdtBalance +=
            lender1.getLendingPrice(address(weth), address(usdt)) *
            250 finney;
        assertEq(yusdtAsset.balance(), expectedUsdtBalance);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDeposits() public {
        // Deposit 1
        user1.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 1 ether);
        assertEq(elf.balance(), 1 ether);
        assertEq(elf.balanceOf(address(user1)), 1 ether);

        // Deposit 2
        user2.approve(address(weth), address(elf));
        user2.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 2 ether);
        assertEq(elf.balance(), 2 ether);
        assertEq(elf.balanceOf(address(user2)), 1 ether);

        // Deposit 3
        user3.approve(address(weth), address(elf));
        user3.call_deposit(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(elf.balance(), 3 ether);
        assertEq(elf.balanceOf(address(user3)), 1 ether);
    }

    function test_multipleWETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);

        // 3 deposits
        user1.approve(address(weth), address(elf));
        user2.approve(address(weth), address(elf));
        user3.approve(address(weth), address(elf));
        user1.call_deposit(address(elf), 1 ether);
        user2.call_deposit(address(elf), 1 ether);
        user3.call_deposit(address(elf), 1 ether);
        assertEq(weth.balanceOf(address(user1)), 999 ether);
        assertEq(weth.balanceOf(address(user2)), 999 ether);
        assertEq(weth.balanceOf(address(user3)), 999 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        assertEq(dai.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 Dai/ 1 ETH
        assertEq(tusd.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 tusd/ 1 ETH
        assertEq(usdc.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 usdc/ 1 ETH
        assertEq(usdt.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 usdt/ 1 ETH

        // 3 withdraws
        user1.call_withdraw(address(elf), 1 ether);
        user2.call_withdraw(address(elf), 1 ether);
        user3.call_withdraw(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000 ether);
        assertEq(tusd.balanceOf(address(lender1)), 1000 ether);
        assertEq(usdc.balanceOf(address(lender1)), 1000 ether);
        assertEq(usdt.balanceOf(address(lender1)), 1000 ether);

        // validate ending balance
        assertEq(weth.balanceOf(address(user1)), 1000 ether);
        assertEq(weth.balanceOf(address(user2)), 1000 ether);
        assertEq(weth.balanceOf(address(user3)), 1000 ether);
    }

    function test_multipleETHDepositsAndWithdraws() public {
        // verify starting balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);

        // 3 deposits
        user1.call_depositETH(address(elf), 1 ether);
        user2.call_depositETH(address(elf), 1 ether);
        user3.call_depositETH(address(elf), 1 ether);
        assertEq(address(user1).balance, 999 ether);
        assertEq(address(user2).balance, 999 ether);
        assertEq(address(user3).balance, 999 ether);
        assertEq(elf.totalSupply(), 3 ether);
        assertEq(weth.balanceOf(address(lender1)), 3 ether);
        assertEq(dai.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 Dai/ 1 ETH
        assertEq(tusd.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 tusd/ 1 ETH
        assertEq(usdc.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 usdc/ 1 ETH
        assertEq(usdt.balanceOf(address(lender1)), 998500 finney); // 100 - 3/4 * 2 usdt/ 1 ETH

        // 3 withdraws
        user1.call_withdrawETH(address(elf), 1 ether);
        user2.call_withdrawETH(address(elf), 1 ether);
        user3.call_withdrawETH(address(elf), 1 ether);
        assertEq(elf.totalSupply(), 0 ether);
        assertEq(weth.balanceOf(address(strategy)), 0 ether);
        assertEq(weth.balanceOf(address(lender1)), 0 ether);
        assertEq(dai.balanceOf(address(lender1)), 1000 ether);
        assertEq(tusd.balanceOf(address(lender1)), 1000 ether);
        assertEq(usdc.balanceOf(address(lender1)), 1000 ether);
        assertEq(usdt.balanceOf(address(lender1)), 1000 ether);

        // validate ending balance
        assertEq(address(user1).balance, 1000 ether);
        assertEq(address(user2).balance, 1000 ether);
        assertEq(address(user3).balance, 1000 ether);
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    // require for withdraw tests to work
    receive() external payable {}
}
