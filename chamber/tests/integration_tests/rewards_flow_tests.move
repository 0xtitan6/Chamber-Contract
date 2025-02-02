#[test_only]
module chamber::reward_flow_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin;
    
    use chamber::rewards::{Self, RewardPool};
    use chamber::stake::{Self, Stake, StakeRegistry};  
    use chamber::config::{Self, Config};
    use chamber::treasury::{Self, Treasury};

    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;
    const VALIDATOR1: address = @0xA1;
    
    // Reduced stake amounts to prevent overflow
    const USER1_STAKE: u64 = 100 * 1_000_000_000; // 100 SUI
    const USER2_STAKE: u64 = 200 * 1_000_000_000; // 200 SUI 
    const USER3_STAKE: u64 = 300 * 1_000_000_000; // 300 SUI

    // Standard reward amount
    const REWARD_AMOUNT: u64 = 10 * 1_000_000_000; // 10 SUI
    
    // Fee structure
    const HIGH_COMMISSION: u64 = 2000;      // 20%

    // Error codes
    const ERR_WRONG_DISTRIBUTION: u64 = 1;
    const ERR_WRONG_COMMISSION: u64 = 2;

    #[test]
    fun test_multi_user_reward_distribution() {
        let mut scenario = test::begin(ADMIN);

        // Setup
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

        // Create stake for USER1
        next_tx(&mut scenario, USER1);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing(USER1_STAKE, ctx(&mut scenario));
            
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

        // Create stake for USER2
        next_tx(&mut scenario, USER2);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing(USER2_STAKE, ctx(&mut scenario));
            
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

        // Create stake for USER3
        next_tx(&mut scenario, USER3);
        {
            let mut registry = test::take_shared<StakeRegistry>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);
            
            let payment = coin::mint_for_testing(USER3_STAKE, ctx(&mut scenario));
            
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

        // Process rewards
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

            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        // Users claim rewards
        let user1_reward: u64;
        next_tx(&mut scenario, USER1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            let stake1 = test::take_from_sender<Stake>(&scenario);

            let reward1 = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake1,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            user1_reward = coin::value(&reward1);
            coin::burn_for_testing(reward1);

            test::return_to_sender(&scenario, stake1);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
        };

        let user2_reward: u64;
        next_tx(&mut scenario, USER2);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            let stake2 = test::take_from_sender<Stake>(&scenario);

            let reward2 = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake2,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            user2_reward = coin::value(&reward2);
            assert!(user2_reward > user1_reward, ERR_WRONG_DISTRIBUTION);
            coin::burn_for_testing(reward2);

            test::return_to_sender(&scenario, stake2);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
        };

        let user3_reward: u64;
        next_tx(&mut scenario, USER3);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let registry = test::take_shared<StakeRegistry>(&scenario);
            let stake3 = test::take_from_sender<Stake>(&scenario);

            let reward3 = rewards::claim_rewards(
                &mut pool,
                &registry,
                &stake3,
                &mut treasury,
                ctx(&mut scenario)
            );
            
            user3_reward = coin::value(&reward3);
            assert!(user3_reward > user2_reward, ERR_WRONG_DISTRIBUTION);
            coin::burn_for_testing(reward3);

            test::return_to_sender(&scenario, stake3);
            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(registry);
        };
        
        test::end(scenario);
    }

    #[test]
    fun test_validator_commission_rates() {
        let mut scenario = test::begin(ADMIN);

        // Initialize modules
        {
            rewards::init_for_testing(ctx(&mut scenario));
            config::init_for_testing(ctx(&mut scenario));
            treasury::init_for_testing(ctx(&mut scenario));
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
                test::ctx(&mut scenario)
            );

            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Process rewards
        next_tx(&mut scenario, VALIDATOR1);
        {
            let mut pool = test::take_shared<RewardPool>(&scenario);
            let mut treasury = test::take_shared<Treasury>(&scenario);
            let mut config = test::take_shared<Config>(&scenario);

            // Get the protocol fee and commission rate from config
            let actual_protocol_fee = config::get_protocol_fee(&config);
            let actual_commission_rate = config::get_validator_commission(&config, VALIDATOR1);

            let reward_coin = coin::mint_for_testing(REWARD_AMOUNT, ctx(&mut scenario));

            // Get expected commission first
            let expected_commission = rewards::calculate_validator_commission(
                REWARD_AMOUNT,
                actual_protocol_fee,
                actual_commission_rate
            );

            // Add rewards
            rewards::add_validator_rewards(
                &mut pool,
                VALIDATOR1,
                reward_coin,
                &mut config,
                &mut treasury,
                ctx(&mut scenario)
            );

            // Get actual rewards after adding
            let actual_validator_rewards = treasury::get_validator_rewards(&treasury, VALIDATOR1);

            assert!(
                actual_validator_rewards == expected_commission,
                ERR_WRONG_COMMISSION
            );

            test::return_shared(pool);
            test::return_shared(treasury);
            test::return_shared(config);
        };

        test::end(scenario);
    }
}