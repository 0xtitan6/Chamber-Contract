// restake_strategy.move
module chamber::restake_strategy {
   use sui::coin::{ Coin};
   use sui::sui::SUI;
   use sui::event;
   use sui::vec_map::{Self, VecMap};

   const E_STRATEGY_NOT_ACTIVE: u64 = 1;
   const E_THRESHOLD_NOT_MET: u64 = 2;
   const E_NO_VALIDATORS: u64 = 3;

   public struct RESTAKE_STRATEGY has drop {}

   public struct Strategy has key {
       id: UID,
       is_active: bool,
       min_threshold: u64,
       max_threshold: u64,
       target_apy: u64,
       validator_scores: VecMap<address, u64>
   }

   public struct StrategyExecuted has copy, drop {
       strategy_id: address,
       amount: u64,
       validator: address,
       timestamp: u64
   }

   fun init(_: RESTAKE_STRATEGY, ctx: &mut TxContext) {
       let strategy = Strategy {
           id: object::new(ctx),
           is_active: true,
           min_threshold: 1_000_000_000, // 1 SUI
           max_threshold: 1_000_000_000_000, // 1000 SUI
           target_apy: 500, // 5.00%
           validator_scores: vec_map::empty()
       };
       transfer::share_object(strategy);
   }

   public fun execute_strategy(
       strategy: &mut Strategy,
       amount: u64,
       payment: Coin<SUI>,
       ctx: &mut TxContext
   ): (address, Coin<SUI>) {
       assert!(strategy.is_active, E_STRATEGY_NOT_ACTIVE);
       assert!(amount >= strategy.min_threshold, E_THRESHOLD_NOT_MET);
       assert!(amount <= strategy.max_threshold, E_THRESHOLD_NOT_MET);
       assert!(!vec_map::is_empty(&strategy.validator_scores), E_NO_VALIDATORS);

       let best_validator = select_best_validator(strategy);
       
       event::emit(StrategyExecuted {
           strategy_id: object::uid_to_address(&strategy.id),
           amount,
           validator: best_validator,
           timestamp: tx_context::epoch(ctx)
       });

       (best_validator, payment)
   }

   public fun add_validator(
       strategy: &mut Strategy, 
       validator: address,
       score: u64
   ) {
       vec_map::insert(&mut strategy.validator_scores, validator, score);
   }

   public fun update_validator_score(
       strategy: &mut Strategy,
       validator: address,
       new_score: u64
   ) {
       assert!(vec_map::contains(&strategy.validator_scores, &validator), E_NO_VALIDATORS);
       vec_map::insert(&mut strategy.validator_scores, validator, new_score);
   }

   fun select_best_validator(strategy: &Strategy): address {
       let validators = vec_map::keys(&strategy.validator_scores);
       let mut best_validator = *vector::borrow(&validators, 0);
       let mut highest_score = 0;
       let mut i = 0;
       let len = vector::length(&validators);
       
       while (i < len) {
           let validator = *vector::borrow(&validators, i);
           let score = *vec_map::get(&strategy.validator_scores, &validator);
           if (score > highest_score) {
               highest_score = score;
               best_validator = validator;
           };
           i = i + 1;
       };
       best_validator
   }

   #[test_only]
   public fun init_for_testing(ctx: &mut TxContext) {
       init(RESTAKE_STRATEGY {}, ctx)
   }
}