module chamber::restake_vault {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::event::emit;  // Changed to direct import of emit

    const E_INSUFFICIENT_BALANCE: u64 = 0;

    public struct RESTAKE_VAULT has drop {}

    public struct RestakeVault has key {
        id: UID,
        balance: u64,
        total_restaked: u64,
        rewards_pool: u64,
        validator_balances: Table<address, u64>,
        treasury_cap: TreasuryCap<SUI>
    }

    public struct VaultDeposit has copy, drop {
        amount: u64,
        validator: address,
        timestamp: u64
    }

    public struct VaultWithdraw has copy, drop {
        amount: u64,
        validator: address,
        timestamp: u64
    }

    fun init(_: RESTAKE_VAULT, ctx: &mut TxContext) {
        // Empty init function - vault creation moved to create_vault
    }

    public fun create_vault(
        _witness: RESTAKE_VAULT,
        treasury_cap: TreasuryCap<SUI>,
        ctx: &mut TxContext
    ) {
        let vault = RestakeVault {
            id: object::new(ctx),
            balance: 0,
            total_restaked: 0,
            rewards_pool: 0,
            validator_balances: table::new(ctx),
            treasury_cap
        };
        transfer::share_object(vault);
    }

    // Getter functions remain the same
    public fun get_total_balance(vault: &RestakeVault): u64 {
        vault.balance
    }

    public fun get_total_staked(vault: &RestakeVault): u64 {
        vault.total_restaked
    }

    public fun get_validator_balance(vault: &RestakeVault, validator: address): u64 {
        if (table::contains(&vault.validator_balances, validator)) {
            *table::borrow(&vault.validator_balances, validator)
        } else {
            0
        }
    }

    public fun get_rewards_pool(vault: &RestakeVault): u64 {
        vault.rewards_pool
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        // Initialize the module
        init(RESTAKE_VAULT {}, ctx);
        
        // Create a test treasury cap
        let treasury_cap = coin::create_treasury_cap_for_testing<SUI>(ctx);
        
        // Create and share the vault
        create_vault(RESTAKE_VAULT {}, treasury_cap, ctx);
    }

    #[test_only]
    public fun create_vault_for_testing(
        treasury_cap: TreasuryCap<SUI>,
        ctx: &mut TxContext
    ) {
        create_vault(RESTAKE_VAULT {}, treasury_cap, ctx)
    }

    #[test_only]
    public fun deposit_for_testing(
        vault: &mut RestakeVault,
        payment: Coin<SUI>,
        validator: address,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        transfer::public_transfer(payment, tx_context::sender(ctx));

        vault.balance = vault.balance + amount;
        vault.total_restaked = vault.total_restaked + amount;

        if (!table::contains(&vault.validator_balances, validator)) {
            table::add(&mut vault.validator_balances, validator, amount);
        } else {
            let balance = table::borrow_mut(&mut vault.validator_balances, validator);
            *balance = *balance + amount;
        };

        emit(VaultDeposit {  // Changed to direct emit call
            amount,
            validator,
            timestamp: tx_context::epoch(ctx)
        });
    }

    #[test_only]
    public fun withdraw_for_testing(
        vault: &mut RestakeVault,
        amount: u64,
        validator: address,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(vault.balance >= amount, E_INSUFFICIENT_BALANCE);
        
        let validator_balance = table::borrow_mut(&mut vault.validator_balances, validator);
        assert!(*validator_balance >= amount, E_INSUFFICIENT_BALANCE);

        vault.balance = vault.balance - amount;
        *validator_balance = *validator_balance - amount;

        emit(VaultWithdraw {  // Changed to direct emit call
            amount,
            validator,
            timestamp: tx_context::epoch(ctx)
        });

        coin::mint(&mut vault.treasury_cap, amount, ctx)
    }
}