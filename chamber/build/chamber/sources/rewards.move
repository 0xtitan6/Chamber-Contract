module chamber::rewards {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::balance;
    use sui::event;
    
    use chamber::math;
    use chamber::stake::{Stake, StakeRegistry};
    use chamber::config::{Self, Config};
    use chamber::treasury::{Self, Treasury};

    /// Error codes
    const E_NO_REWARDS: u64 = 0;
    const E_INVALID_AMOUNT: u64 = 1;

    /// Constants
    const BASIS_POINTS: u64 = 10000;

    /// Tracks rewards and distributions 
    public struct RewardPool has key {
        id: UID,
        /// Total rewards per validator
        validator_rewards: Table<address, u64>,
        /// Total claimed per staker 
        claimed_rewards: Table<address, u64>
    }

    /// Events
    public struct RewardAdded has copy, drop {
        validator: address,
        amount: u64
    }

    public struct RewardClaimed has copy, drop {
        staker: address,
        amount: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(RewardPool {
            id: object::new(ctx),
            validator_rewards: table::new(ctx),
            claimed_rewards: table::new(ctx)
        });
    }

    public fun add_validator_rewards(
        pool: &mut RewardPool,
        validator: address,
        reward: Coin<SUI>,
        config: &mut Config,
        treasury: &mut Treasury,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&reward);
        assert!(amount > 0, E_INVALID_AMOUNT);

        let protocol_fee = config::get_protocol_fee(config);
        let validator_commission = config::get_validator_commission(config, validator);

        // Use the calculate_validator_commission function
        let commission = calculate_validator_commission(amount, protocol_fee, validator_commission);

        // Update validator rewards with commission amount
        if (!table::contains(&pool.validator_rewards, validator)) {
            table::add(&mut pool.validator_rewards, validator, 0);
        };
        let validator_rewards = table::borrow_mut(&mut pool.validator_rewards, validator);
        *validator_rewards = *validator_rewards + commission;

        // Add commission to treasury
        treasury::add_validator_reward(treasury, validator, commission);

        // Store reward 
        treasury::deposit_stake(
            treasury,
            config,
            validator,
            reward,
            ctx
        );

        event::emit(RewardAdded {
            validator,
            amount: commission
        });

        event::emit(RewardAdded {
            validator,
            amount: commission
        });
    }
    
    /// Claim rewards for a stake
    public fun claim_rewards(
        pool: &mut RewardPool,
        registry: &StakeRegistry,
        stake: &Stake,
        treasury: &mut Treasury,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let staker = tx_context::sender(ctx);
        
        // Calculate rewards
        let reward_amount = calculate_rewards(pool, registry, stake);
        assert!(reward_amount > 0, E_NO_REWARDS);

        // Update claimed rewards
        if (!table::contains(&pool.claimed_rewards, staker)) {
            table::add(&mut pool.claimed_rewards, staker, 0);
        };
        let claimed = table::borrow_mut(&mut pool.claimed_rewards, staker);
        *claimed = *claimed + reward_amount;

        // Get the treasury balance and mint reward coins
        let reward_coin = coin::from_balance(
            balance::split(treasury::borrow_stake_balance_mut(treasury), reward_amount), 
            ctx
        );
        
        event::emit(RewardClaimed {
            staker,
            amount: reward_amount
        });

        reward_coin
    }

    /// Calculate pending rewards for a stake
    public fun calculate_rewards(
        pool: &RewardPool,
        registry: &StakeRegistry, 
        stake: &Stake
    ): u64 {
        let validator = chamber::stake::get_validator(stake);
        if (!table::contains(&pool.validator_rewards, validator)) {
            return 0
        };

        let validator_rewards = *table::borrow(&pool.validator_rewards, validator);
        let stake_amount = chamber::stake::get_amount(stake);
        let total_stake = chamber::stake::get_validator_stake(registry, validator);

        if (total_stake == 0 || validator_rewards == 0) {
            return 0
        };

        math::mul_div(stake_amount, validator_rewards, total_stake)
    }

    public fun calculate_validator_commission(
        reward_amount: u64,
        protocol_fee: u64,
        commission_rate: u64
    ): u64 {
        // Use math::mul_div consistently for both calculations
        let protocol_fee_amount = math::mul_div(reward_amount, protocol_fee, BASIS_POINTS);
        let after_protocol_fee = reward_amount - protocol_fee_amount;
        
        // Calculate commission using math::mul_div
        math::mul_div(after_protocol_fee, commission_rate, BASIS_POINTS)
    }

    /// Get total validator rewards
    public fun get_validator_rewards(pool: &RewardPool, validator: address): u64 {
        if (!table::contains(&pool.validator_rewards, validator)) {
            return 0
        };
        *table::borrow(&pool.validator_rewards, validator)
    }

    /// Get claimed rewards
    public fun get_claimed_rewards(pool: &RewardPool, staker: address): u64 {
        if (!table::contains(&pool.claimed_rewards, staker)) {
            return 0
        };
        *table::borrow(&pool.claimed_rewards, staker)
    }

    // === Test Functions ===
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}