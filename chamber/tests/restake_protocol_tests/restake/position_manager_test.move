// tests/restake_protocol_tests/restake/position_manager_tests.move
#[test_only]
module chamber::position_manager_tests {
   use sui::test_scenario::{Self as test, next_tx, ctx};
   use chamber::position_manager::{Self, PositionManager};

   const ADMIN: address = @0xAD;
   const USER: address = @0xB0B;
   const MIN_STAKE: u64 = 1_000_000;
   const DURATION: u64 = 30; // 30 epochs

   #[test]
   fun test_initialization() {
       let mut scenario = test::begin(ADMIN);
       {
           position_manager::init_for_testing(ctx(&mut scenario));
       };
       test::end(scenario);
   }

   #[test]
    fun test_create_position() {
        let mut scenario = test::begin(ADMIN);
        {
            position_manager::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, USER);
        {
            let mut manager = test::take_shared<PositionManager>(&scenario);
            
            position_manager::create_position(
                &mut manager,
                MIN_STAKE,
                0,
                DURATION,
                ctx(&mut scenario)
            );

            assert!(position_manager::get_total_positions(&manager) == 1, 0);
            assert!(position_manager::get_active_positions(&manager) == 1, 1);

            test::return_shared(manager);
        };
        test::end(scenario);
    }

    #[test]
    fun test_multiple_positions() {
        let mut scenario = test::begin(ADMIN);
        {
            position_manager::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, USER);
        {
            let mut manager = test::take_shared<PositionManager>(&scenario);
            
            position_manager::create_position(
                &mut manager,
                MIN_STAKE,
                0,
                DURATION,
                ctx(&mut scenario)
            );

            position_manager::create_position(
                &mut manager,
                MIN_STAKE * 2,
                1,
                DURATION * 2,
                ctx(&mut scenario)
            );

            assert!(position_manager::get_total_positions(&manager) == 2, 0);
            assert!(position_manager::get_active_positions(&manager) == 2, 1);

            test::return_shared(manager);
        };
        test::end(scenario);
    }
}