module alcove::Pool {

    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use alcove::Config;
    use alcove::Coin;
    use alcove::JumpRateModel;

    friend alcove::Ticket;

    const EINVALID_ADDRESS: u64 = 301;

    struct Pool<phantom CoinType> has key, store {
        token: coin::Coin<CoinType>,
        borrowed_amount: u64,
        deposited_amount: u64,
        supply_rate: u64,
        borrow_rate: u64,
        supply_index: u64,
        borrow_index: u64,
        last_update_timestamp: u64
    }

    public entry fun initialize<CoinType>(
        account: &signer,
        supply_rate_init: u64,
        borrow_rate_init: u64,
    ) {
        assert!(Config::admin_address() == signer::address_of(account), EINVALID_ADDRESS);
        move_to(account, Pool<CoinType>{
            token: coin::zero<CoinType>(),
            borrowed_amount: 0u64,
            deposited_amount: 0u64,
            supply_rate: supply_rate_init,
            borrow_rate: borrow_rate_init,
            supply_index: 1u64,
            borrow_index: 1u64,
            last_update_timestamp: 0u64
        });
    }

    public(friend) fun deposit<CoinType>(account: &signer, amount: u64) acquires Pool {
        refresh();
        let coins = coin::withdraw<CoinType>(account, amount);
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        coin::merge(&mut pool.token, coins);
        pool.deposited_amount = pool.deposited_amount + amount;
    }

    public(friend) fun withdraw<CoinType>(account: &signer, amount: u64) acquires Pool {
        refresh();
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        let coins = coin::extract<CoinType>(&mut pool.token, amount);
        coin::deposit<CoinType>(signer::address_of(account), coins);
        pool.deposited_amount = pool.deposited_amount - amount;
    }

    public(friend) fun borrow<CoinType>(account: &signer, amount: u64) acquires Pool {
        refresh();
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        let coins = coin::extract<CoinType>(&mut pool.token, amount);
        if (!coin::is_account_registered<CoinType>(signer::address_of(account))) {
            managed_coin::register<CoinType>(account);
        };
        coin::deposit<CoinType>(signer::address_of(account), coins);
        pool.borrowed_amount = pool.borrowed_amount + amount;
    }

    public(friend) fun repay<CoinType>(account: &signer, amount: u64) acquires Pool {
        refresh();
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        let coins = coin::withdraw<CoinType>(account, amount);
        coin::merge<CoinType>(&mut pool.token, coins);
        pool.deposited_amount = pool.deposited_amount + amount;
    }

    public(friend) fun refresh() acquires Pool {
        refresh_pool<Coin::ETH>();
        refresh_pool<Coin::BTC>();
        refresh_pool<aptos_coin::AptosCoin>();
    }

    public(friend) fun get_index<CoinType>(): (u64, u64) acquires Pool {
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        (pool.supply_index, pool.borrow_index)
    }

    fun refresh_pool<CoinType>() acquires Pool {
        let pool = borrow_global_mut<Pool<CoinType>>(Config::admin_address());
        let time_delta = timestamp::now_seconds() - pool.last_update_timestamp;
        let utilization = utilization_rate<CoinType>(pool.borrowed_amount, pool.deposited_amount);
        let (borrow_index_new, borrow_rate_year) = borrow_index_new<CoinType>(time_delta, pool.borrow_index, utilization);
        let (supply_index_new, supply_rate_year) = supply_index_new<CoinType>(time_delta, utilization, borrow_rate_year, pool.supply_index);
        pool.borrow_index = borrow_index_new;
        pool.supply_index = supply_index_new;
        pool.borrow_rate = borrow_rate_year;
        pool.supply_rate = supply_rate_year;
        pool.last_update_timestamp = timestamp::now_seconds();
    }

    fun borrow_index_new<CoinType>(time_delta: u64, borrow_index_old: u64, utilization_rate: u64):
    (u64, u64)
    {
        // return borrow_index_new and borrow_rate_year
        // calculate current borrow_rate_year with current utilization
        let borrow_rate_year = JumpRateModel::borrow_rate<CoinType>(utilization_rate);
        // calculate current borrow_rate_per_second
        let borrow_rate_per_second = borrow_rate_year / (365 * 24 * 60 * 60);
        // calculate borrow_index_new = (borrow_rate_per_second * timeDelta + 1) * borrow_index_old
        let borrow_index_new = (borrow_rate_per_second * time_delta + 1) * borrow_index_old;
        (borrow_index_new, borrow_rate_year)
    }

    fun supply_index_new<CoinType>(time_delta: u64, utilization_rate: u64, borrow_rate_year: u64, supply_index_old: u64): (u64, u64) {
        // return supply_index_new and supply_rate_year
        let supply_rate_year = JumpRateModel::deposit_rate<CoinType>(utilization_rate, borrow_rate_year);
        // calculate current supply_rate_per_second
        let supply_rate_per_second = supply_rate_year / (365 * 24 * 60 * 60);
        // calculate supply_index_new = (supply_rate_per_second * timeDelta + 1) * supply_index_old
        let supply_index_new = (supply_rate_per_second * time_delta + 1) * supply_index_old;
        (supply_index_new, supply_rate_year)
    }

    fun utilization_rate<CoinType>(total: u64, borrowed: u64): u64 {
        borrowed / total
    }

}