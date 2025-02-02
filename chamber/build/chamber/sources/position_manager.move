module chamber::position_manager {
   use sui::table::{Self, Table};

   public struct POSITION_MANAGER has drop {}

   public struct Position has store {
       amount: u64,
       restake_type: u8,
       start_time: u64,
       duration: u64,
       rewards_earned: u64,
       is_active: bool
   }

   public struct PositionManager has key {
       id: UID,
       positions: Table<address, vector<Position>>,
       total_positions: u64,
       active_positions: u64
   }

   fun init(_: POSITION_MANAGER, ctx: &mut TxContext) {
       transfer::share_object(PositionManager {
           id: object::new(ctx),
           positions: table::new(ctx),
           total_positions: 0,
           active_positions: 0
       })
   }

   public fun create_position(
        manager: &mut PositionManager,
        amount: u64,
        restake_type: u8,
        duration: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let position = Position {
            amount,
            restake_type,
            start_time: tx_context::epoch(ctx),
            duration,
            rewards_earned: 0,
            is_active: true
        };

        if (!table::contains(&manager.positions, sender)) {
            table::add(&mut manager.positions, sender, vector::singleton(position));
        } else {
            let positions = table::borrow_mut(&mut manager.positions, sender);
            vector::push_back(positions, position);
        };

        manager.total_positions = manager.total_positions + 1;
        manager.active_positions = manager.active_positions + 1;
    }

    // position_manager.move
    public fun get_total_positions(manager: &PositionManager): u64 {
        manager.total_positions
    }

    public fun get_active_positions(manager: &PositionManager): u64 {
        manager.active_positions
    }

   #[test_only]
   public fun init_for_testing(ctx: &mut TxContext) {
       init(POSITION_MANAGER {}, ctx)
   }
}