// tests/restake_protocol_tests/restake/restake_manager_tests.move
#[test_only]
module chamber::restake_manager_tests {
   use sui::test_scenario::{Self as test, next_tx, ctx};
   use sui::coin::mint_for_testing;
   use sui::sui::SUI;
   use chamber::restake_manager::{Self, RestakeManager};

   const ADMIN: address = @0xAD;
   const USER: address = @0xB0B;
   const MIN_STAKE: u64 = 1_000_000;

   #[test]
   fun test_initialization() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_manager::init_for_testing(ctx(&mut scenario));
       };
       test::end(scenario);
   }

   #[test]
   fun test_create_restake() {
       let mut scenario = test::begin(ADMIN);
       {
           restake_manager::init_for_testing(ctx(&mut scenario));
       };
       
       next_tx(&mut scenario, ADMIN);
       {
           let mut manager = test::take_shared<RestakeManager>(&scenario);
           
           restake_manager::create_restake_type(
               &mut manager,
               true,
               MIN_STAKE,
               MIN_STAKE * 1000,
               5,
               0,
               ctx(&mut scenario)
           );

           test::return_shared(manager);
       };

       next_tx(&mut scenario, USER);
       {
           let mut manager = test::take_shared<RestakeManager>(&scenario);
           let coins = mint_for_testing<SUI>(MIN_STAKE, ctx(&mut scenario));
           
           restake_manager::create_restake(
               &mut manager,
               coins,
               0,
               ctx(&mut scenario)
           );

           test::return_shared(manager);
       };
       test::end(scenario);
   }
}