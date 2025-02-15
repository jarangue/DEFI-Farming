// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./DappToken.sol";
import "./LPToken.sol";

/**
 * @title Proportional Token Farm
 * @notice Una granja de staking donde las recompensas se distribuyen proporcionalmente al total stakeado.
 */
contract TokenFarm {
    //
    // Variables de estado
    //
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    uint256 public constant REWARD_PER_BLOCK = 1e18; // Recompensa por bloque (total para todos los usuarios)
    uint256 public totalStakingBalance; // Total de tokens en staking
    uint256 public feePercentage = 5; // Porcentaje de comisión (puede ser modificado por el owner)

    address[] public stakers;
    mapping(address => StakingUserInfo) public stakingUserInfo;

    // Eventos
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed user, uint256 amount);
    event FeeCollected(address indexed owner, uint256 amount);

    // Struct para almacenar la información del staking de un usuario
    struct StakingUserInfo {
        uint256 stakingBalance; 
        uint256 checkpoint;
        uint256 pendingRewards; 
        bool hasStaked; 
        bool isStaking; 
    }

    // Constructor
    constructor(DAppToken _dappToken, LPToken _lpToken) {
        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;
    }

    /**
     * @notice Deposita tokens LP para staking.
     * @param _amount Cantidad de tokens LP a depositar.
     */
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        // Transferencia segura de tokens LP
        require(lpToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        StakingUserInfo storage user = stakingUserInfo[msg.sender];

        // Si usuario no hizo staking, agregarlo a la lista de stakers
        if (!user.hasStaked) {
            stakers.push(msg.sender);
            user.hasStaked = true;
        }

        // Actualizar el balance de staking del usuario y el total staking
        user.stakingBalance += _amount;
        totalStakingBalance += _amount;

        // Marcar como staking
        user.isStaking = true;

        // Actualizar el checkpoint y distribuir recompensas
        user.checkpoint = block.number;
        distributeRewards(msg.sender);

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Retira todos los tokens LP en staking.
     */
    function withdraw() external {
        StakingUserInfo storage user = stakingUserInfo[msg.sender];
        require(user.isStaking, "You are not staking");
        require(user.stakingBalance > 0, "No staking balance to withdraw");

        // Calcular las recompensas antes de retirar
        distributeRewards(msg.sender);

        uint256 amountToWithdraw = user.stakingBalance;
        user.stakingBalance = 0;
        totalStakingBalance -= amountToWithdraw;
        user.isStaking = false;

        // Transferencia segura de tokens LP
        require(lpToken.transfer(msg.sender, amountToWithdraw), "Transfer failed");

        // Eliminar al usuario de la lista de stakers si ya no tiene balance
        if (user.stakingBalance == 0) {
            user.hasStaked = false;
            for (uint256 i = 0; i < stakers.length; i++) {
                if (stakers[i] == msg.sender) {
                    stakers[i] = stakers[stakers.length - 1];
                    stakers.pop();
                    break;
                }
            }
        }

        emit Withdraw(msg.sender, amountToWithdraw);
    }

    /**
     * @notice Reclama recompensas pendientes.
     */
    function claimRewards() external {
        StakingUserInfo storage user = stakingUserInfo[msg.sender];
        uint256 pendingAmount = user.pendingRewards;
        require(pendingAmount > 0, "No rewards to claim");

        // Restablecer las recompensas pendientes
        user.pendingRewards = 0;

        // Calcular y cobrar comisión
        uint256 fee = (pendingAmount * feePercentage) / 100;
        uint256 amountAfterFee = pendingAmount - fee;

        // Transferencia segura de recompensas
        dappToken.mint(msg.sender, amountAfterFee);
        dappToken.mint(owner, fee);

        emit RewardsClaimed(msg.sender, amountAfterFee);
        emit FeeCollected(owner, fee);
    }

    /**
     * @notice Distribuye recompensas a todos los usuarios en staking.
     */
    function distributeRewardsAll() external onlyOwner {
        for (uint256 i = 0; i < stakers.length; i++) {
            address userAddress = stakers[i];
            distributeRewards(userAddress);
        }
    }

    /**
     * @notice Calcula y distribuye las recompensas proporcionalmente al staking total.
     * @dev La función toma en cuenta el porcentaje de tokens que cada usuario tiene en staking con respecto
     *      al total de tokens en staking (`totalStakingBalance`).
     */
    function distributeRewards(address beneficiary) private {
        StakingUserInfo storage user = stakingUserInfo[beneficiary];
        uint256 blocksPassed = block.number - user.checkpoint;

        if (blocksPassed == 0 || totalStakingBalance == 0) {
            user.checkpoint = block.number; // Actualizar checkpoint incluso si no hay recompensas
            return;
        }

        // Calcular la participación proporcional del usuario
        uint256 userShare = (user.stakingBalance * 1e18) / totalStakingBalance;
        uint256 rewards = (REWARD_PER_BLOCK * blocksPassed * userShare) / 1e18;

        // Recompensas pendientes del usuario actualizadas
        user.pendingRewards += rewards;

        // Actualizar el checkpoint
        user.checkpoint = block.number;

        emit RewardsDistributed(beneficiary, rewards);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can execute this");
        _;
    }
}