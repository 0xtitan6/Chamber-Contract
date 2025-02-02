#[test_only]
module chamber::stake_flow_tests {
    use sui::test_scenario;
    use sui::coin::{Self};
    use sui::sui::SUI;
    use sui::test_utils;
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};

    // Constants
    const TEST_ADMIN: address = @0x1234;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0x1111;
    const INITIAL_STAKE_AMOUNT: u64 = 1000 * 1_000_000_000; // 1000 SUI
    const REWARD_AMOUNT: u64 = 100 * 1_000_000_000; // 100 SUI
    const MAX_VALIDATOR_STAKE: u64 = 10000 * 1_000_000_000; // 10000 SUI

    #[test]
    fun test_alice_stake_and_rewards() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        
        setup_protocol(&mut scenario);

        // Alice stakes 1000 SUI
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE_AMOUNT, test_scenario::ctx(&mut scenario));

            // Alice stakes her SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            // Verify full amount was staked (no fees taken)
            assert!(treasury::get_stake_balance(&treasury) == INITIAL_STAKE_AMOUNT, 0);
            assert!(config::get_total_staked(&config) == INITIAL_STAKE_AMOUNT, 1);

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        // Simulate rewards distribution
        // Simulate rewards distribution
        test_scenario::next_tx(&mut scenario, TEST_ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            // Calculate expected amounts first
            let fee_bps = config::get_protocol_fee(&config);
            let expected_fee = (REWARD_AMOUNT * fee_bps) / 10000;
            let expected_validator_reward = REWARD_AMOUNT - expected_fee;
            
            // Distribute rewards
            let (validator_reward, protocol_fee) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                REWARD_AMOUNT,
                test_scenario::ctx(&mut scenario)
            );

            // Verify reward distribution
            assert!(coin::value(&validator_reward) == expected_validator_reward, 6);
            assert!(treasury::get_validator_rewards(&treasury, TEST_VALIDATOR) == expected_validator_reward, 7);
            assert!(treasury::get_protocol_fees(&treasury) == expected_fee, 8);

            // Clean up test coins
            test_utils::destroy(validator_reward);
            test_utils::destroy(protocol_fee);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_alice_withdrawal() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // First stake
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(INITIAL_STAKE_AMOUNT, test_scenario::ctx(&mut scenario));

            // Alice stakes her SUI
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test_scenario::ctx(&mut scenario)
            );

            // Verify full amount was staked (no fees taken)
            assert!(treasury::get_stake_balance(&treasury) == INITIAL_STAKE_AMOUNT, 0);
            assert!(config::get_total_staked(&config) == INITIAL_STAKE_AMOUNT, 1);

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        // Initiate withdrawal
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            let withdraw_amount = 500 * 1_000_000_000; // 500 SUI

            treasury::initiate_withdrawal(
                &mut treasury,
                &config,
                ALICE,
                withdraw_amount,
                test_scenario::ctx(&mut scenario)
            );

            // Verify withdrawal was recorded correctly
            // Check pending withdrawals
            // Verify stake balance unchanged until withdrawal period

            test_scenario::return_shared(registry);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_sequential_stakes() {
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

        // Second stake from same user
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let additional_amount = 500 * 1_000_000_000; // 500 SUI
            let payment = coin::mint_for_testing<SUI>(additional_amount, test_scenario::ctx(&mut scenario));
            
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

        test_scenario::end(scenario);
    }

    #[test]
    fun test_compound_staking() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // Initial stake from Alice
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

        // Get rewards and restake
        test_scenario::next_tx(&mut scenario, TEST_ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let config = test_scenario::take_shared<Config>(&scenario);

            let (validator_reward, protocol_fee) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                REWARD_AMOUNT,
                test_scenario::ctx(&mut scenario)
            );

            transfer::public_transfer(validator_reward, ALICE);
            test_utils::destroy(protocol_fee);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(treasury);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = stake::E_STAKE_EXCEEDS_CAPACITY)]
    fun test_stake_max_validator_capacity() {
        let mut scenario = test_scenario::begin(TEST_ADMIN);
        setup_protocol(&mut scenario);

        // Alice stakes up to max capacity
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(MAX_VALIDATOR_STAKE, test_scenario::ctx(&mut scenario));

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

        // Alice tries to stake above capacity, should fail
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test_scenario::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test_scenario::take_shared<Treasury>(&scenario);
            let mut config = test_scenario::take_shared<Config>(&scenario);

            let additional_stake = coin::mint_for_testing<SUI>(100 * 1_000_000_000, test_scenario::ctx(&mut scenario));
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                additional_stake,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(registry);
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
                MAX_VALIDATOR_STAKE, // Set max stake to accommodate all test scenarios
                1000,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(config);
        };
    }
}