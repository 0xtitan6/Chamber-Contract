// restake_strategy_tests.move
#[test_only]
module chamber::restake_strategy_tests {
   use sui::test_scenario::{Self as test, next_tx, ctx};
   use sui::coin::{Self, mint_for_testing};
   use sui::sui::SUI;
   use chamber::restake_strategy::{Self, Strategy};

   const ADMIN: address = @0xAD;
   const VALIDATOR_1: address = @0xB0B;
   const VALIDATOR_2: address = @0xCAFE;
   const USER: address = @0xDEAD;

   const STAKE_AMOUNT: u64 = 1_000_000_000;

   #[test]
   fun test_initialization() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_strategy::init_for_testing(ctx(&mut scenario));
       };
       test::end(scenario);
   }

   #[test]
   fun test_execute_strategy() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_strategy::init_for_testing(ctx(&mut scenario));
       };

       next_tx(&mut scenario, USER);
       {
           let mut strategy = test::take_shared<Strategy>(&scenario);
           
           // Add validators with scores
           restake_strategy::add_validator(&mut strategy, VALIDATOR_1, 100);
           restake_strategy::add_validator(&mut strategy, VALIDATOR_2, 50);
           
           let payment = mint_for_testing<SUI>(STAKE_AMOUNT, ctx(&mut scenario));

           let (validator, coin) = restake_strategy::execute_strategy(
               &mut strategy,
               STAKE_AMOUNT,
               payment,
               ctx(&mut scenario)
           );

           assert!(validator == VALIDATOR_1, 0); // Should select validator with highest score
           assert!(coin::value(&coin) == STAKE_AMOUNT, 1);

           transfer::public_transfer(coin, USER);
           test::return_shared(strategy);
       };
       test::end(scenario);
   }

   #[test]
   #[expected_failure(abort_code = restake_strategy::E_THRESHOLD_NOT_MET)]
   fun test_execute_strategy_below_threshold() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_strategy::init_for_testing(ctx(&mut scenario));
       };

       next_tx(&mut scenario, USER);
       {
           let mut strategy = test::take_shared<Strategy>(&scenario);
           restake_strategy::add_validator(&mut strategy, VALIDATOR_1, 100);
           
           let payment = mint_for_testing<SUI>(STAKE_AMOUNT / 2, ctx(&mut scenario));

           let (_, coin) = restake_strategy::execute_strategy(
               &mut strategy,
               STAKE_AMOUNT / 2,
               payment,
               ctx(&mut scenario)
           );

           transfer::public_transfer(coin, USER);
           test::return_shared(strategy);
       };
       test::end(scenario);
   }

   #[test]
   #[expected_failure(abort_code = restake_strategy::E_NO_VALIDATORS)]
   fun test_execute_strategy_no_validators() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_strategy::init_for_testing(ctx(&mut scenario));
       };

       next_tx(&mut scenario, USER);
       {
           let mut strategy = test::take_shared<Strategy>(&scenario);
           let payment = mint_for_testing<SUI>(STAKE_AMOUNT, ctx(&mut scenario));

           let (_, coin) = restake_strategy::execute_strategy(
               &mut strategy,
               STAKE_AMOUNT,
               payment,
               ctx(&mut scenario)
           );

           transfer::public_transfer(coin, USER);
           test::return_shared(strategy);
       };
       test::end(scenario);
   }
}