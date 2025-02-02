#[test_only]
module chamber::exchange_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use chamber::exchange::{Self, ExchangeRate};
    
    const ADMIN: address = @0xAD;
    const PRECISION: u64 = 1_000_000_000;
    const STAKE_AMOUNT: u64 = 1_000_000_000;

    #[test]
    fun test_basic_exchange_rate() {
        let mut scenario = test::begin(ADMIN);
        
        {
            exchange::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let rate = test::take_shared<ExchangeRate>(&scenario);
            
            assert!(exchange::get_rate(&rate) == PRECISION, 0);
            assert!(exchange::get_total_sui(&rate) == 0, 1);
            assert!(exchange::get_total_csui(&rate) == 0, 2);
            assert!(exchange::sui_to_csui(&rate, STAKE_AMOUNT) == STAKE_AMOUNT, 3);
            assert!(exchange::csui_to_sui(&rate, STAKE_AMOUNT) == STAKE_AMOUNT, 4);
            
            test::return_shared(rate);
        };

        next_tx(&mut scenario, ADMIN);
        {
            let mut rate = test::take_shared<ExchangeRate>(&scenario);
            
            exchange::update_rate_stake(&mut rate, STAKE_AMOUNT, ctx(&mut scenario));
            
            assert!(exchange::get_total_sui(&rate) == STAKE_AMOUNT, 5);
            assert!(exchange::get_total_csui(&rate) == STAKE_AMOUNT, 6);
            assert!(exchange::get_rate(&rate) == PRECISION, 7);
            
            test::return_shared(rate);
        };

        next_tx(&mut scenario, ADMIN);
        {
            let mut rate = test::take_shared<ExchangeRate>(&scenario);
            
            exchange::update_rate_unstake(&mut rate, STAKE_AMOUNT, ctx(&mut scenario));
            
            assert!(exchange::get_total_sui(&rate) == 0, 8);
            assert!(exchange::get_total_csui(&rate) == 0, 9);
            assert!(exchange::get_rate(&rate) == PRECISION, 10);
            
            test::return_shared(rate);
        };

        test::end(scenario);
    }

}