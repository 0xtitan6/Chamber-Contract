// delegation_pool.move
module chamber::delegation_pool {
   use sui::coin::{Self, Coin, TreasuryCap};
   use sui::sui::SUI;
   use sui::table::{Self, Table};
   use sui::event;
   use chamber::csui::{Self, CSUI};
   use chamber::stake::{Self, StakeRegistry};
   use chamber::treasury::{Treasury};
   use chamber::config::{Config};

   // Error codes
   const E_POOL_FULL: u64 = 1;
   const E_INVALID_AMOUNT: u64 = 2;
   const E_POOL_INACTIVE: u64 = 3;

   public struct DELEGATION_POOL has drop {}

   public struct DelegationPool has key {
       id: UID,
       total_sui_staked: u64,
       total_csui_supply: u64,
       active_delegations: u64,
       capacity: u64,
       is_active: bool,
       delegator_balances: Table<address, DelegatorPosition>,
       rewards_rate: u64,
       min_delegation: u64,
       treasury_cap: TreasuryCap<CSUI>
   }

   public struct DelegatorPosition has store {
       sui_amount: u64,
       csui_amount: u64,
       last_reward_time: u64
   }

   public struct PoolDeposit has copy, drop {
        delegator: address,
        sui_amount: u64,
        csui_amount: u64,
        timestamp: u64,
        validator: address  // Added validator field
   }

   fun init(_: DELEGATION_POOL, ctx: &mut TxContext) {
       
   }

   public fun create_pool(
        _witness: DELEGATION_POOL,
        treasury_cap: TreasuryCap<CSUI>, 
        ctx: &mut TxContext
    ) {
        let pool = DelegationPool {
            id: object::new(ctx),
            total_sui_staked: 0,
            total_csui_supply: 0,
            active_delegations: 0,
            capacity: 1_000_000_000_000, // 1000 SUI
            is_active: true,
            delegator_balances: table::new(ctx),
            rewards_rate: 500, // 5.00% APY
            min_delegation: 1_000_000_000, // 1 SUI
            treasury_cap
        };
        transfer::share_object(pool);
    }

    public entry fun deposit(
        pool: &mut DelegationPool,
        registry: &mut StakeRegistry, 
        treasury: &mut Treasury,
        config: &mut Config,
        validator: address,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let sui_amount = coin::value(&payment);
        assert!(pool.is_active, E_POOL_INACTIVE);
        assert!(sui_amount >= pool.min_delegation, E_INVALID_AMOUNT);
        assert!(pool.total_sui_staked + sui_amount <= pool.capacity, E_POOL_FULL);

        // Calculate cSUI amount to mint
        let csui_amount = calculate_csui_amount(pool, sui_amount);

        // Delegate through stake module
        stake::stake(
            registry,
            treasury,
            config,
            validator,
            payment,
            ctx
        );
        
        // Mint cSUI to delegator
        let csui_coins = coin::mint(&mut pool.treasury_cap, csui_amount, ctx);
        let sender = tx_context::sender(ctx);
        
        // Update delegator position
        if (!table::contains(&pool.delegator_balances, sender)) {
            table::add(&mut pool.delegator_balances, sender, DelegatorPosition {
                sui_amount,
                csui_amount,
                last_reward_time: tx_context::epoch(ctx)
            });
            pool.active_delegations = pool.active_delegations + 1;
        } else {
            let position = table::borrow_mut(&mut pool.delegator_balances, sender);
            position.sui_amount = position.sui_amount + sui_amount;
            position.csui_amount = position.csui_amount + csui_amount;
        };

        // Update pool totals
        pool.total_sui_staked = pool.total_sui_staked + sui_amount;
        pool.total_csui_supply = pool.total_csui_supply + csui_amount;
        
        // Transfer minted cSUI to user
        transfer::public_transfer(csui_coins, sender);

        event::emit(PoolDeposit {
            delegator: sender,
            sui_amount,
            csui_amount,
            timestamp: tx_context::epoch(ctx),
            validator
        });
    }

   fun calculate_csui_amount(pool: &DelegationPool, sui_amount: u64): u64 {
       if (pool.total_csui_supply == 0) {
           sui_amount // Initial 1:1 rate
       } else {
           (sui_amount * pool.total_csui_supply) / pool.total_sui_staked
       }
   }

   public fun get_exchange_rate(pool: &DelegationPool): u64 {
       if (pool.total_sui_staked == 0) {
           1_000_000_000 // 1:1 rate in basis points
       } else {
           (pool.total_sui_staked * 1_000_000_000) / pool.total_csui_supply
       }
   }

    public fun get_total_sui_staked(pool: &DelegationPool): u64 {
        pool.total_sui_staked
    }

   #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let treasury_cap = csui::create_treasury_cap_for_testing(ctx);
        create_pool(DELEGATION_POOL {}, treasury_cap, ctx)
    }

    #[test_only]
    public fun update_capacity_for_testing(pool: &mut DelegationPool, new_capacity: u64) {
        pool.capacity = new_capacity;
    }
}