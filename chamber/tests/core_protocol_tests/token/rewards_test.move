#[test_only]
module chamber::rewards_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin;
    use sui::sui::SUI;
    
    use chamber::rewards::{Self, RewardPool};
    use chamber::stake::{Self, Stake, StakeRegistry}; 
    use chamber::config::{Self, Config};
    use chamber::treasury::{Self, Treasury};

    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2; 
    const VALIDATOR1: address = @0xA1;
    
    const STAKE_AMOUNT: u64 = 1000000000;
    const REWARD_AMOUNT: u64 = 100000000;
    const HIGH_COMMISSION: u64 = 2000; // 20%

    // Error constants
    const ERR_INVALID_REWARD: u64 = 0;
    const ERR_WRONG_VALUE: u64 = 1;

    #[test]
    fun test_basic_rewards_flow() {
        let mut scenario = test::begin(ADMIN);

        // Initialize modules
        {
            rewards::init_for_testing(ctx(&mut scenario));
            config::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
            stake::init_for_testing(ctx(&mut scenario));
        };

        // Setup validator
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender(&scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                10000 * 1_000_000_000,
                HIGH_COMMISSION,
                ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Create stake via staking
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT, ctx(&mut scenario));

            // Use the stake function to create and register the stake
            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                payment,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // First add funds to treasury
        next_tx(&mut scenario, VALIDATOR1);
        {
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let reward_coin = coin::mint_for_testing<SUI>(REWARD_AMOUNT, ctx(&mut scenario));
            
            treasury::deposit_stake(
                &mut treasury, 
                &mut config,
                VALIDATOR1,
                reward_coin,
                ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_shared(treasury);
        };

        // Then add rewards to pool
        next_tx(&mut scenario, VALIDATOR1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let reward_coin = coin::mint_for_testing(REWARD_AMOUNT, ctx(&mut scenario));
            
            rewards::add_validator_rewards(
                &mut pool,
                VALIDATOR1,
                reward_coin,
                &mut config,
                &mut treasury,
                ctx(&mut scenario)
            );

            assert!(rewards::get_validator_rewards(&pool, VALIDATOR1) > 0, ERR_INVALID_REWARD);
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_shared(pool);
        };

        // Get the stake object for claiming rewards
        next_tx(&mut scenario, USER1);
        let stake = test::take_from_sender<Stake>(&scenario);

        // Claim rewards
        next_tx(&mut scenario, USER1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);

            let reward = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake,
                &mut treasury,
                ctx(&mut scenario)
            );

            let reward_value = coin::value(&reward);
            assert!(reward_value > 0, ERR_WRONG_VALUE);

            coin::burn_for_testing(reward);

            test::return_shared(registry);
            test::return_shared(pool);
            test::return_shared(treasury);
        };

        // Clean up
        next_tx(&mut scenario, USER1);
        test::return_to_sender(&scenario, stake);
        test::end(scenario);
    }
    
    #[test]
    fun test_multiple_stakers() {
        let mut scenario = test::begin(ADMIN);

        // Initialize modules
        {
            rewards::init_for_testing(ctx(&mut scenario));
            config::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
            stake::init_for_testing(ctx(&mut scenario));
        };

        // Setup validator with lower commission
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender(&scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                10000 * 1_000_000_000,
                1000, // 10% commission
                ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // First user stakes
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(50000000, ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                payment,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Second user stakes
        next_tx(&mut scenario, USER2);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(100000000, ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                payment,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Add rewards to treasury and pool
        next_tx(&mut scenario, VALIDATOR1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            // First add reward to treasury
            let treasury_reward = coin::mint_for_testing<SUI>(1000000000, ctx(&mut scenario));
            treasury::deposit_stake(
                &mut treasury,
                &mut config,
                VALIDATOR1,
                treasury_reward,
                ctx(&mut scenario)
            );
            
            // Now add reward to pool
            let pool_reward = coin::mint_for_testing(1000000000, ctx(&mut scenario));
            rewards::add_validator_rewards(
                &mut pool,
                VALIDATOR1,
                pool_reward,
                &mut config,
                &mut treasury,
                ctx(&mut scenario)
            );

            test::return_shared(config);
            test::return_shared(treasury);
            test::return_shared(pool);
        };

        // Get stakes from users
        next_tx(&mut scenario, USER1);
        let stake1 = test::take_from_sender<Stake>(&scenario);
        
        next_tx(&mut scenario, USER2);
        let stake2 = test::take_from_sender<Stake>(&scenario);

        // First staker claims rewards
        next_tx(&mut scenario, USER1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            
            let reward1 = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake1,
                &mut treasury,
                ctx(&mut scenario)
            );

            let reward1_value = coin::value(&reward1);
            assert!(reward1_value > 0, ERR_WRONG_VALUE);
            coin::burn_for_testing(reward1);
            
            test::return_shared(registry);
            test::return_shared(pool);
            test::return_shared(treasury);
        };
        
        // Second staker claims rewards
        next_tx(&mut scenario, USER2);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            
            let reward2 = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake2,
                &mut treasury,
                ctx(&mut scenario)
            );

            let reward2_value = coin::value(&reward2);
            assert!(reward2_value > 0, ERR_WRONG_VALUE);
            coin::burn_for_testing(reward2);
            
            test::return_shared(registry);
            test::return_shared(pool);
            test::return_shared(treasury);
        };

        // Clean up
        next_tx(&mut scenario, USER1);
        test::return_to_sender(&scenario, stake1);
        next_tx(&mut scenario, USER2); 
        test::return_to_sender(&scenario, stake2);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = rewards::E_NO_REWARDS)]
    fun test_claim_no_rewards() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize modules
        {
            rewards::init_for_testing(ctx(&mut scenario));
            config::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
            stake::init_for_testing(ctx(&mut scenario));
        };

        // Setup validator
        next_tx(&mut scenario, ADMIN);
        {
            let mut config = test::take_shared<Config>(&scenario);
            let admin_cap = test::take_from_sender(&scenario);
            
            config::add_or_update_validator(
                &admin_cap,
                &mut config,
                VALIDATOR1,
                true,
                10000 * 1_000_000_000,
                1000,
                ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Create stake via staking
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let payment = coin::mint_for_testing<SUI>(STAKE_AMOUNT, ctx(&mut scenario));

            stake::stake(
                &mut registry,
                &mut treasury,
                &mut config,
                VALIDATOR1,
                payment,
                ctx(&mut scenario)
            );

            test::return_shared(registry);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Get the stake object
        next_tx(&mut scenario, USER1);
        let stake = test::take_from_sender<Stake>(&scenario);

        // Try to claim non-existent rewards (should fail)
        next_tx(&mut scenario, USER1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            
            let reward = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            coin::burn_for_testing(reward);
            
            test::return_shared(registry);
            test::return_shared(pool);
            test::return_shared(treasury);
        };

        // Clean up
        next_tx(&mut scenario, USER1);
        test::return_to_sender(&scenario, stake);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = rewards::E_INVALID_AMOUNT)]  
    fun test_add_zero_rewards() {
        let mut scenario = test::begin(ADMIN);

        {
            rewards::init_for_testing(ctx(&mut scenario));
            config::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, VALIDATOR1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            let zero_coin = coin::mint_for_testing(0, ctx(&mut scenario));
            
            rewards::add_validator_rewards(
                &mut pool,
                VALIDATOR1,
                zero_coin,
                &mut config,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            test::return_shared(config);
            test::return_shared(treasury);
            test::return_shared(pool);
        };

        test::end(scenario);
    }

    #[test]
    fun test_calculate_validator_commission() {
        let reward_amount = 10000000000; // 10 SUI
        let protocol_fee = 300; // 3%
        let commission_rate = 2000; // 20%
        
        let commission = rewards::calculate_validator_commission(
            reward_amount,
            protocol_fee,
            commission_rate
        );
        
        // Expected: 10 SUI - 3% = 9.7 SUI, then 20% of 9.7 = 1.94 SUI
        assert!(commission == 1940000000, 1);
    }
}