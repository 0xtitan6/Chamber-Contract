module chamber::treasury {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::event;
    use chamber::config::{Self, Config, AdminCap};

    /// Error codes
    const E_INSUFFICIENT_BALANCE: u64 = 0;
    const E_VALIDATOR_NOT_ACTIVE: u64 = 3;

    /// Treasury object to manage protocol funds
    public struct Treasury has key {
        id: UID,
        /// Main staking pool balance
        stake_balance: Balance<SUI>,
        /// Protocol fees collected
        protocol_fees: Balance<SUI>,
        /// Track validator rewards
        validator_rewards: Table<address, u64>,
        /// Track pending withdrawals
        pending_withdrawals: Table<address, WithdrawalInfo>
    }

    /// Withdrawal tracking
    public struct WithdrawalInfo has store {
        amount: u64,
        unlock_time: u64
    }

    /// Events
    public struct StakeDeposited has copy, drop {
        validator: address,
        amount: u64,
        fee_amount: u64
    }

    public struct RewardDistributed has copy, drop {
        validator: address,
        amount: u64,
        fee_amount: u64
    }

    public struct WithdrawalInitiated has copy, drop {
        staker: address,
        amount: u64,
        unlock_time: u64
    }

    /// Event for validator reward tracking
    public struct ValidatorRewardAdded has copy, drop {
        validator: address,
        amount: u64
    }

    fun init(ctx: &mut TxContext) {
        let treasury = Treasury {
            id: object::new(ctx),
            stake_balance: balance::zero(),
            protocol_fees: balance::zero(),
            validator_rewards: table::new(ctx),
            pending_withdrawals: table::new(ctx)
        };
        
        transfer::share_object(treasury);
    }

    public fun deposit_stake(
        treasury: &mut Treasury,
        config: &mut Config,
        validator: address,
        payment: Coin<SUI>,
        _ctx: &mut TxContext
    ) {
        assert!(config::is_validator_active(config, validator, 0), E_VALIDATOR_NOT_ACTIVE);
        
        let amount = coin::value(&payment);
        
        balance::join(&mut treasury.stake_balance, coin::into_balance(payment));

        config::increase_total_staked(config, amount);

        event::emit(StakeDeposited {
            validator,
            amount,
            fee_amount: 0
        });
    }

    public fun withdraw_stake(
        treasury: &mut Treasury,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(amount > 0, E_INSUFFICIENT_BALANCE);
        assert!(balance::value(&treasury.stake_balance) >= amount, E_INSUFFICIENT_BALANCE);
        coin::from_balance(balance::split(&mut treasury.stake_balance, amount), ctx)
    }

    public fun distribute_rewards(
        _admin: &AdminCap,
        treasury: &mut Treasury,
        config: &Config,
        validator: address,
        amount: u64,
        ctx: &mut TxContext
    ): (Coin<SUI>, Coin<SUI>) {
        assert!(amount > 0, E_INSUFFICIENT_BALANCE);
        assert!(balance::value(&treasury.stake_balance) >= amount, E_INSUFFICIENT_BALANCE);

        let fee_bps = config::get_protocol_fee(config);
        let fee_amount = (amount * fee_bps) / 10000;
        let validator_reward = amount - fee_amount;

        // Split fees first
        let fee_balance = balance::split(&mut treasury.stake_balance, fee_amount);
        // Add to protocol fees balance
        balance::join(&mut treasury.protocol_fees, fee_balance);

        // Create validator reward coin
        let reward_coin = coin::from_balance(
            balance::split(&mut treasury.stake_balance, validator_reward),
            ctx
        );

        // Create zero coin for protocol fee (since we stored it)
        let fee_coin = coin::zero<SUI>(ctx);

        let current_rewards = if (table::contains(&treasury.validator_rewards, validator)) {
            *table::borrow(&treasury.validator_rewards, validator)
        } else {
            table::add(&mut treasury.validator_rewards, validator, 0);
            0
        };
        *table::borrow_mut(&mut treasury.validator_rewards, validator) = current_rewards + validator_reward;

        event::emit(RewardDistributed {
            validator,
            amount: validator_reward,
            fee_amount
        });

        (reward_coin, fee_coin)
    }

    public fun initiate_withdrawal(
        treasury: &mut Treasury,
        config: &Config,
        staker: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_INSUFFICIENT_BALANCE);
        assert!(balance::value(&treasury.stake_balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        let unlock_time = tx_context::epoch(ctx) + config::get_withdrawal_delay(config);
        
        let withdrawal_info = WithdrawalInfo {
            amount,
            unlock_time
        };
        
        table::add(&mut treasury.pending_withdrawals, staker, withdrawal_info);

        event::emit(WithdrawalInitiated {
            staker,
            amount,
            unlock_time
        });
    }

    public fun add_validator_reward(treasury: &mut Treasury, validator: address, amount: u64) {
        // Initialize validator rewards if not present
        if (!table::contains(&treasury.validator_rewards, validator)) {
            table::add(&mut treasury.validator_rewards, validator, 0);
        };

        // Add reward amount to validator's total
        let validator_rewards = table::borrow_mut(&mut treasury.validator_rewards, validator);
        *validator_rewards = *validator_rewards + amount;

        // Emit event for tracking purposes
        event::emit(ValidatorRewardAdded {
            validator,
            amount
        });
    }

    // Add this function to your treasury module
    public fun borrow_stake_balance_mut(treasury: &mut Treasury): &mut Balance<SUI> {
        &mut treasury.stake_balance
    }

    public fun get_stake_balance(treasury: &Treasury): u64 {
        balance::value(&treasury.stake_balance)
    }

    public fun get_protocol_fees(treasury: &Treasury): u64 {
        balance::value(&treasury.protocol_fees)
    }

    public fun get_validator_rewards(
        treasury: &Treasury,
        validator: address
    ): u64 {
        if (table::contains(&treasury.validator_rewards, validator)) {
            *table::borrow(&treasury.validator_rewards, validator)
        } else {
            0
        }
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}