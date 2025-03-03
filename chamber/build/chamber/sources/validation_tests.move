#[test_only]
module chamber::validation_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use chamber::config::{Self, AdminCap, Config};
    use chamber::exchange::{Self, ExchangeRate};
    use chamber::treasury::{Self, Treasury};
    use chamber::validation;

    const ADMIN: address = @0xAD;

    #[test]
    fun test_system_state() {
        let mut scenario = test::begin(ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
            next_tx(&mut scenario, ADMIN);
            
            let config = test::take_shared<Config>(&scenario);
            validation::validate_system_state(&config);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = validation::E_SYSTEM_PAUSED)]
    fun test_paused_system() {
        let mut scenario = test::begin(ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
            next_tx(&mut scenario, ADMIN);
            
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            config::set_pause_status(&admin_cap, &mut config, true);
            validation::validate_system_state(&config);
            test::return_shared(config);
            test::return_to_sender(&scenario, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    fun test_balance_validation() {
        let mut scenario = test::begin(ADMIN);
        {
            treasury::init_for_testing(ctx(&mut scenario));
            exchange::init_for_testing(ctx(&mut scenario));
            next_tx(&mut scenario, ADMIN);
            
            let treasury = test::take_shared<Treasury>(&scenario);
            let exchange = test::take_shared<ExchangeRate>(&scenario);
            validation::validate_balances(&treasury, &exchange);
            test::return_shared(treasury);
            test::return_shared(exchange);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = validation::E_INVALID_VALIDATOR)]
    fun test_invalid_validator() {
        let mut scenario = test::begin(ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
            next_tx(&mut scenario, ADMIN);
            
            let config = test::take_shared<Config>(&scenario);
            validation::validate_validator(&config, @0x1);
            test::return_shared(config);
        };
        test::end(scenario);
    }

    #[test]
    fun test_stake_amount_validation() {
        let min_stake = validation::get_min_stake();
        let max_stake = validation::get_max_stake();

        validation::validate_stake_amount(min_stake);
        validation::validate_stake_amount(max_stake);
    }

    #[test]
    #[expected_failure(abort_code = validation::E_BELOW_MINIMUM)]
    fun test_stake_below_minimum() {
        let min_stake = validation::get_min_stake();
        validation::validate_stake_amount(min_stake - 1);
    }

    #[test]
    #[expected_failure(abort_code = validation::E_ABOVE_MAXIMUM)]
    fun test_stake_above_maximum() {
        let max_stake = validation::get_max_stake();
        validation::validate_stake_amount(max_stake + 1);
    }

    #[test]
    fun test_withdraw_validation() {
        validation::validate_withdraw_amount(1000, 500);
    }

    #[test]
    #[expected_failure(abort_code = validation::E_INVALID_AMOUNT)]
    fun test_invalid_withdraw() {
        validation::validate_withdraw_amount(1000, 1001);
    }
}
