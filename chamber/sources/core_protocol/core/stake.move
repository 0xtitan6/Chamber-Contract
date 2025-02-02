module chamber::stake {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::event;
    use chamber::config::{Self, Config};
    use chamber::treasury::{Self, Treasury};
    use chamber::validation;

    /// Error codes
    const E_STAKE_NOT_FOUND: u64 = 1;
    const E_STAKE_MISMATCH: u64 = 2;
    const E_STAKE_EXCEEDS_CAPACITY: u64 = 3;
    const E_VALIDATOR_NOT_ACTIVE: u64 = 4;
    const E_ALREADY_PROCESSED: u64 = 5;
    const E_NOT_IN_EMERGENCY: u64 = 6;

    /// User's stake information
    public struct Stake has key, store {
        id: UID,
        validator: address,
        amount: u64,
        staked_at: u64
    }

    /// Registry for all stakes
    public struct StakeRegistry has key {
        id: UID,
        /// Track active stakes
        stakes: Table<address, ID>,  // staker -> stake id
        /// Track total stakes per validator
        validator_stakes: Table<address, u64>,  // validator -> total stake amount
        /// Track emergency withdrawal status
        emergency_processed: bool
    }

    /// Events
    public struct StakeCreated has copy, drop {
        staker: address,
        validator: address,
        amount: u64
    }

    public struct StakeWithdrawn has copy, drop {
        staker: address,
        validator: address,
        amount: u64
    }

    public struct EmergencyWithdrawalProcessed has copy, drop {
        total_amount: u64,
        processor: address
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(StakeRegistry {
            id: object::new(ctx),
            stakes: table::new(ctx),
            validator_stakes: table::new(ctx),
            emergency_processed: false
        });
    }

    public entry fun emergency_withdraw(
        registry: &mut StakeRegistry,
        treasury: &mut Treasury,
        config: &mut Config,
        ctx: &mut TxContext
    ) {
        // Verify emergency mode is active
        assert!(config::is_emergency_mode(config), E_NOT_IN_EMERGENCY);
        // Verify not already processed
        assert!(!registry.emergency_processed, E_ALREADY_PROCESSED);

        // Get total amount available for withdrawal
        let withdrawal_amount = treasury::get_stake_balance(treasury);

        if (withdrawal_amount > 0) {
            // Process withdrawal
            let withdrawal_coin = treasury::withdraw_stake(treasury, withdrawal_amount, ctx);
            
            // Update total staked amount
            config::decrease_total_staked(config, withdrawal_amount);

            // Transfer funds back to treasury for distribution
            transfer::public_transfer(withdrawal_coin, tx_context::sender(ctx));

            // Emit event
            event::emit(EmergencyWithdrawalProcessed {
                total_amount: withdrawal_amount,
                processor: tx_context::sender(ctx)
            });
        };

        // Mark emergency as processed
        registry.emergency_processed = true;
    }

    public entry fun stake(
        registry: &mut StakeRegistry,
        treasury: &mut Treasury,
        config: &mut Config,
        validator: address,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        
        // Validate using validation module
        validation::validate_stake_for_system(config, amount);

        // Get validator info and current stake
        let (is_active, max_stake, _commission_bps) = config::get_validator_config(config, validator);
        assert!(is_active, E_VALIDATOR_NOT_ACTIVE);
        
        let current_stake = get_validator_stake(registry, validator);
        
        // Check validator capacity
        assert!(
            current_stake + amount <= max_stake, 
            E_STAKE_EXCEEDS_CAPACITY
        );
        
        let staker = tx_context::sender(ctx);

        // Update validator's total stake
        if (table::contains(&registry.validator_stakes, validator)) {
            let validator_total = table::borrow_mut(&mut registry.validator_stakes, validator);
            *validator_total = *validator_total + amount;
        } else {
            table::add(&mut registry.validator_stakes, validator, amount);
        };

        // Send funds to treasury first
        treasury::deposit_stake(treasury, config, validator, payment, ctx);

        // Create new stake record
        let stake = Stake {
            id: object::new(ctx),
            validator,
            amount,
            staked_at: tx_context::epoch(ctx)
        };

        let stake_id = object::uid_to_inner(&stake.id);
        
        // If there's an existing stake, clean it up
        if (table::contains(&registry.stakes, staker)) {
            let _old_id = table::remove(&mut registry.stakes, staker);
        };
        
        // Store stake reference and transfer object
        table::add(&mut registry.stakes, staker, stake_id);
        transfer::transfer(stake, staker);

        event::emit(StakeCreated {
            staker,
            validator,
            amount
        });
    }

    /// Withdraw staked SUI
    public entry fun withdraw(
        registry: &mut StakeRegistry,
        stake: Stake,
        treasury: &mut Treasury,
        config: &Config,
        ctx: &mut TxContext
    ) {
        let staker = tx_context::sender(ctx);
        assert!(table::contains(&registry.stakes, staker), E_STAKE_NOT_FOUND);
        
        let saved_stake_id = table::remove(&mut registry.stakes, staker);
        assert!(object::uid_to_inner(&stake.id) == saved_stake_id, E_STAKE_MISMATCH);
        
        let Stake { id, validator, amount, staked_at: _ } = stake;
        
        // Update validator's total stake
        if (table::contains(&registry.validator_stakes, validator)) {
            let validator_total = table::borrow_mut(&mut registry.validator_stakes, validator);
            *validator_total = *validator_total - amount;
            
            // Remove validator entry if total is 0
            if (*validator_total == 0) {
                table::remove(&mut registry.validator_stakes, validator);
            };
        };

        object::delete(id);

        treasury::initiate_withdrawal(
            treasury,
            config,
            staker,
            amount,
            ctx
        );

        event::emit(StakeWithdrawn {
            staker,
            validator,
            amount
        });
    }

    // === Getter Functions ===

    public fun get_validator(stake: &Stake): address {
        stake.validator
    }

    public fun get_validator_stake(registry: &StakeRegistry, validator: address): u64 {
        if (table::contains(&registry.validator_stakes, validator)) {
            *table::borrow(&registry.validator_stakes, validator)
        } else {
            0
        }
    }

    public fun get_amount(stake: &Stake): u64 {
        stake.amount
    }

    public fun get_stake_time(stake: &Stake): u64 {
        stake.staked_at
    }

    public fun get_stake_id(
        registry: &StakeRegistry,
        staker: address
    ): ID {
        assert!(table::contains(&registry.stakes, staker), E_STAKE_NOT_FOUND);
        *table::borrow(&registry.stakes, staker)
    }

    public fun has_stake(registry: &StakeRegistry, staker: address): bool {
        table::contains(&registry.stakes, staker)
    }

    public fun is_emergency_processed(registry: &StakeRegistry): bool {
        registry.emergency_processed
    }

    // === Test Functions ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    public fun create_stake_for_testing(
        validator: address,
        amount: u64,
        staked_at: u64,
        ctx: &mut TxContext
    ): Stake {
        Stake {
            id: object::new(ctx),
            validator,
            amount,
            staked_at
        }
    }

    #[test_only]
    public fun reset_emergency_for_testing(registry: &mut StakeRegistry) {
        registry.emergency_processed = false;
    }
}