module chamber::restake_manager {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::sui::SUI;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::tx_context::{Self, TxContext};

    public struct RESTAKE_MANAGER has drop {}

    public struct RestakeCreated has copy, drop {
        user: address,
        amount: u64,
        restake_type: u8,
        timestamp: u64
    }

    const E_INSUFFICIENT_AMOUNT: u64 = 0;
    const E_INACTIVE_RESTAKE: u64 = 2;
    const E_MAX_CAPACITY: u64 = 4;

    public struct RestakeManager has key {
        id: UID,
        total_restaked: u64,
        active_restakes: u64,
        restake_types: Table<u8, RestakeType>,
        positions: Table<address, RestakePosition>,
        // Remove treasury_cap as we can't create one for SUI
        // treasury_cap: TreasuryCap<SUI>
    }

    public struct RestakeType has store {
        is_active: bool,
        min_amount: u64,
        max_amount: u64,
        reward_rate: u64
    }

    public struct RestakePosition has store {
        amount: u64,
        restake_type: u8,
        rewards_accumulated: u64,
        timestamp: u64
    }

    fun init(_: RESTAKE_MANAGER, ctx: &mut TxContext) {
        let manager = RestakeManager {
            id: object::new(ctx),
            total_restaked: 0,
            active_restakes: 0,
            restake_types: table::new(ctx),
            positions: table::new(ctx),
            // Remove treasury cap initialization
        };
        transfer::share_object(manager);
    }

    public fun create_restake_type(
        manager: &mut RestakeManager,
        is_active: bool,
        min_amount: u64,
        max_amount: u64,
        reward_rate: u64,
        restake_type: u8,
        _ctx: &mut TxContext
    ) {
        let config = RestakeType {
            is_active,
            min_amount,
            max_amount,
            reward_rate
        };
        table::add(&mut manager.restake_types, restake_type, config);
    }

    public entry fun create_restake(
        manager: &mut RestakeManager,
        payment: Coin<SUI>,
        restake_type: u8,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        let restake_config = table::borrow(&manager.restake_types, restake_type);
        
        assert!(restake_config.is_active, E_INACTIVE_RESTAKE);
        assert!(amount >= restake_config.min_amount, E_INSUFFICIENT_AMOUNT);
        assert!(amount <= restake_config.max_amount, E_MAX_CAPACITY);

        transfer::public_transfer(payment, tx_context::sender(ctx));

        let position = RestakePosition {
            amount,
            restake_type,
            rewards_accumulated: 0,
            timestamp: tx_context::epoch(ctx)
        };

        let sender = tx_context::sender(ctx);
        table::add(&mut manager.positions, sender, position);
        manager.total_restaked = manager.total_restaked + amount;
        manager.active_restakes = manager.active_restakes + 1;

        event::emit(RestakeCreated {
            user: sender,
            amount,
            restake_type,
            timestamp: tx_context::epoch(ctx)
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(RESTAKE_MANAGER {}, ctx)
    }
}