#[test_only]
module chamber::withdrawal_flow_tests {
    use sui::test_scenario;
    use sui::coin::{Self};
    use sui::sui::SUI;
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};

    // Constants
    const TEST_ADMIN: address = @0x1234;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0x1111;
    const INITIAL_STAKE_AMOUNT: u64 = 1000 * 1_000_000_000; // 1000 SUI

    #[test]
    fun test_complete_withdrawal() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        
        setup_protocol(&mut scenario);

        // First stake
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE_AMOUNT, test_scenario::ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        // Initiate withdrawal
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            let initial_balance = treasury::get_stake_balance(&treasury);

            treasury::initiate_withdrawal(
                &mut treasury,
                &config,
                ALICE,
                INITIAL_STAKE_AMOUNT,
                test_scenario::ctx(&mut scenario)
            );

            // Verify stake balance remains unchanged
            assert!(treasury::get_stake_balance(&treasury) == initial_balance, 1);

            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_withdrawals() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        
        setup_protocol(&mut scenario);

        // Initial stake
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE_AMOUNT, test_scenario::ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        // First withdrawal request
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            let withdraw_amount = INITIAL_STAKE_AMOUNT / 2;
            let stake_balance = treasury::get_stake_balance(&treasury);

            treasury::initiate_withdrawal(
                &mut treasury,
                &config,
                ALICE,
                withdraw_amount,
                test_scenario::ctx(&mut scenario)
            );

            // Verify balance unchanged
            assert!(treasury::get_stake_balance(&treasury) == stake_balance, 0);

            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_withdrawal_amounts() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        
        setup_protocol(&mut scenario);

        // Initial stake
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE_AMOUNT, test_scenario::ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        // Request partial withdrawal
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);
            
            let partial_amount = INITIAL_STAKE_AMOUNT / 2;
            let initial_balance = treasury::get_stake_balance(&treasury);
            
            treasury::initiate_withdrawal(
                &mut treasury,
                &config,
                ALICE,
                partial_amount,
                test_scenario::ctx(&mut scenario)
            );

            assert!(treasury::get_stake_balance(&treasury) == initial_balance, 0);

            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    fun setup_protocol(scenario: &mut test_scenario::Scenario) {
        test_scenario::next_tx(scenario, TEST_ADMIN);
        {
            config::init_for_testing(test_scenario::ctx(scenario));
            stake::init_for_testing(test_scenario::ctx(scenario));
            treasury::init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, TEST_ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let mut config = test_scenario::take_shared<Config>(scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                10000 * 1_000_000_000, // 10000 SUI max stake
                1000,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(config);
        };
    }
}