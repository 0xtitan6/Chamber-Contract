#[test_only]
module chamber::multi_user_tests {
    use sui::test_scenario::{Self as test, Scenario};
    use sui::coin::{Self};
    use sui::sui::SUI;
    use sui::test_utils;
    use chamber::config::{Self, Config, AdminCap};
    use chamber::stake::{Self, StakeRegistry};
    use chamber::treasury::{Self, Treasury};

    // Test addresses
    const TEST_ADMIN: address = @0x1234;
    const TEST_VALIDATOR: address = @0x5678;
    const ALICE: address = @0x1111;
    const BOB: address = @0x2222;
    
    // Test amounts
    const ALICE_STAKE: u64 = 1000 * 1_000_000_000; // 1000 SUI
    const BOB_STAKE: u64 = 500 * 1_000_000_000;    // 500 SUI
    const REWARD_AMOUNT: u64 = 150 * 1_000_000_000; // 150 SUI
    const MAX_VALIDATOR_STAKE: u64 = 10000 * 1_000_000_000; // 10000 SUI - enough for all stakers

    #[test]
    fun test_multiple_stakers() {
        let mut scenario = test::begin(TEST_ADMIN);
        
        setup_protocol(&mut scenario);

        // Alice stakes first
        test::next_tx(&mut scenario, ALICE);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(ALICE_STAKE, test::ctx(&mut scenario));
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Bob stakes next
        test::next_tx(&mut scenario, BOB);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            let payment = coin::mint_for_testing<SUI>(BOB_STAKE, test::ctx(&mut scenario));
            
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                TEST_VALIDATOR,
                payment,
                test::ctx(&mut scenario)
            );

            // Verify combined stakes
            let total_staked = ALICE_STAKE + BOB_STAKE;
            assert!(treasury::get_stake_balance(&treasury) == total_staked, 0);

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Distribute rewards
        test::next_tx(&mut scenario, TEST_ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let config = test::take_shared<Config>(&scenario);

            let fee_bps = config::get_protocol_fee(&config);
            let protocol_fee = (REWARD_AMOUNT * fee_bps) / 10000;
            let total_reward = REWARD_AMOUNT - protocol_fee;

            let (validator_reward, protocol_fee_coin) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                TEST_VALIDATOR,
                REWARD_AMOUNT,
                test::ctx(&mut scenario)
            );

            // Verify total rewards and fees
            assert!(treasury::get_validator_rewards(&treasury, TEST_VALIDATOR) == total_reward, 1);
            assert!(treasury::get_protocol_fees(&treasury) == protocol_fee, 2);
            
            // Verify the reward coin value matches expected total
            assert!(coin::value(&validator_reward) == total_reward, 3);

            test_utils::destroy(validator_reward);
            test_utils::destroy(protocol_fee_coin);

            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    fun setup_protocol(scenario: &mut Scenario) {
        test::next_tx(scenario, TEST_ADMIN);
        {
            config::init_for_testing(test::ctx(scenario));
            stake::init_for_testing(test::ctx(scenario));
            treasury::init_for_testing(test::ctx(scenario));
        };

        test::next_tx(scenario, TEST_ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(scenario);
            let mut config = test::take_shared<Config>(scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                TEST_VALIDATOR,
                true,
                MAX_VALIDATOR_STAKE, // Set validator capacity high enough for all stakers
                1000,
                test::ctx(scenario)
            );

            test::return_to_sender(scenario, admin_cap);
            test::return_shared(config);
        };
    }
}