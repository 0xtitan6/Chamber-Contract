#[test_only]
module chamber::restake_vault_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self, mint_for_testing};
    use sui::sui::SUI;
    use chamber::restake_vault::{Self, RestakeVault};

    const ADMIN: address = @0xAD;
    const VALIDATOR: address = @0xB0B;
    const USER: address = @0xCAFE;

    const DEPOSIT_AMOUNT: u64 = 1_000_000_000;
    const WITHDRAW_AMOUNT: u64 = 500_000_000;

    fun setup(scenario: &mut test::Scenario) {
        restake_vault::init_for_testing(test::ctx(scenario));
    }

    #[test]
    fun test_initialization() {
        let mut scenario = test::begin(ADMIN);
        setup(&mut scenario);
        test::end(scenario);
    }

    #[test]
    fun test_deposit() {
        let mut scenario = test::begin(ADMIN);
        setup(&mut scenario);

        next_tx(&mut scenario, USER);
        {
            let mut vault = test::take_shared<RestakeVault>(&scenario);
            let payment = mint_for_testing<SUI>(DEPOSIT_AMOUNT, ctx(&mut scenario));

            restake_vault::deposit_for_testing(
                &mut vault,
                payment, 
                VALIDATOR,
                ctx(&mut scenario)
            );

            test::return_shared(vault);
        };
        test::end(scenario);
    }

    #[test]
    fun test_withdraw() {
        let mut scenario = test::begin(ADMIN);
        setup(&mut scenario);

        next_tx(&mut scenario, USER);
        {
            let mut vault = test::take_shared<RestakeVault>(&scenario);
            let payment = mint_for_testing<SUI>(DEPOSIT_AMOUNT, ctx(&mut scenario));

            restake_vault::deposit_for_testing(
                &mut vault,
                payment,
                VALIDATOR,
                ctx(&mut scenario)
            );

            let coin = restake_vault::withdraw_for_testing(
                &mut vault,
                WITHDRAW_AMOUNT,
                VALIDATOR,
                ctx(&mut scenario)
            );

            transfer::public_transfer(coin, USER);
            test::return_shared(vault);
        };
        test::end(scenario);
    }
}