#[test_only]
module chamber::treasury_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{Self};
    use sui::sui::SUI;
    use sui::test_utils;
    
    use chamber::treasury::{Self, Treasury};
    use chamber::config::{Self, Config, AdminCap};

    // Test constants
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const VALIDATOR1: address = @0x42;

    // Error constants
    const E_INSUFFICIENT_BALANCE: u64 = 0;
    const E_VALIDATOR_NOT_ACTIVE: u64 = 3;

    fun setup_test(): Scenario {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize config
        next_tx(&mut scenario, ADMIN);
        {
            config::init_for_testing(ctx(&mut scenario));
        };

        // Initialize treasury
        next_tx(&mut scenario, ADMIN);
        {
            treasury::init_for_testing(ctx(&mut scenario));
        };

        scenario
    }

    #[test]
    fun test_basic_deposit() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            
            // Setup validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000,
                1000,
                test::ctx(&mut scenario)
            );
            
            let stake_amount = 100000000;
            let test_coin = coin::mint_for_testing<SUI>(stake_amount, ctx(&mut scenario));
            
            // Test deposit
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                test_coin,
                ctx(&mut scenario)
            );
            
            // Verify balances
            let protocol_fees = treasury::get_protocol_fees(&treasury);
            let stake_balance = treasury::get_stake_balance(&treasury);
            let total_staked = config::get_total_staked(&config);
            
            assert!(protocol_fees == 0, 0);
            assert!(stake_balance == stake_amount, 1);
            assert!(total_staked == stake_amount, 2);
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_to_address(ADMIN, admin_cap);
        };
        
        test::end(scenario);
    }

    #[test]
    fun test_reward_distribution() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            
            // Setup validator
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000,
                1000,
                test::ctx(&mut scenario)
            );

            // Initial stake
            let stake_amount = 100000000;
            let stake_coin = coin::mint_for_testing<SUI>(stake_amount, ctx(&mut scenario));
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                stake_coin,
                ctx(&mut scenario)
            );
            
            // Distribute rewards
            let reward_amount = 1000000;

            // Calculate expected fee
            let fee_bps = config::get_protocol_fee(&config);
            let expected_fee = (reward_amount * fee_bps) / 10000;
            let expected_validator_reward = reward_amount - expected_fee;

            let (validator_reward, protocol_fee) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                VALIDATOR1,
                reward_amount,
                ctx(&mut scenario)
            );
            
            // Verify reward distribution
            assert!(coin::value(&validator_reward) == expected_validator_reward, 0);
            assert!(treasury::get_validator_rewards(&treasury, VALIDATOR1) == expected_validator_reward, 1);
            assert!(treasury::get_protocol_fees(&treasury) == expected_fee, 2);
            
            // Clean up coins
            test_utils::destroy(validator_reward);
            test_utils::destroy(protocol_fee);
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_to_address(ADMIN, admin_cap);
        };
        
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_VALIDATOR_NOT_ACTIVE, location = chamber::treasury)]
    fun test_deposit_inactive_validator() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            
            // Try deposit without setting up validator
            let test_coin = coin::mint_for_testing<SUI>(100000000, ctx(&mut scenario));
            
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                test_coin,
                ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_shared(treasury);
        };
        
        test::end(scenario);
    }

    #[test]
    fun test_withdrawal_initiation() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);
            
            // Setup validator and deposit
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000,
                1000,
                test::ctx(&mut scenario)
            );

            let stake_coin = coin::mint_for_testing<SUI>(100000000, ctx(&mut scenario));
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                stake_coin,
                ctx(&mut scenario)
            );
            
            // Initiate withdrawal
            treasury::initiate_withdrawal(
                &mut treasury,
                &config,
                USER1,
                50000000,
                ctx(&mut scenario)
            );
            
            // Balance check
            assert!(treasury::get_stake_balance(&treasury) == 100000000, 0);
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_to_address(ADMIN, admin_cap);
        };
        
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_INSUFFICIENT_BALANCE, location = chamber::treasury)]  // Changed location
    fun test_excessive_reward_distribution() {
        let mut scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let admin_cap = test::take_from_address<AdminCap>(&scenario, ADMIN);

            // Need to setup validator and do initial deposit first
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                1000000000,
                1000,
                test::ctx(&mut scenario)
            );

            // Initial stake of 100 SUI
            let stake_coin = coin::mint_for_testing<SUI>(100_000_000_000, ctx(&mut scenario));
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                stake_coin,
                ctx(&mut scenario)
            );
            
            // Try to distribute more rewards than available balance
            let amount = 1000_000_000_000; // 1000 SUI
            let (validator_reward, protocol_fee) = treasury::distribute_rewards(
                &admin_cap,
                &mut treasury,
                &config,
                VALIDATOR1,
                amount,
                ctx(&mut scenario)
            );
            
            test_utils::destroy(validator_reward);
            test_utils::destroy(protocol_fee);
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_to_address(ADMIN, admin_cap);
        };
        
        test::end(scenario);
    }
}