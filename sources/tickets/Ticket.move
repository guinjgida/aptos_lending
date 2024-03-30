module alcove::Ticket {

    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin;
    use alcove::Pool;
    use alcove::Price;
    use alcove::Coin::{BTC, ETH};

    const EACCOUNT_VALUE: u64 = 101;
    const EINVALID_WITHDRAW_AMOUNT: u64 = 102;
    const EINVALID_REPAY_AMOUNT: u64 = 103;
    const EINVALID_BORROW_AMOUNT: u64 = 102;

    struct Alcove<phantom CoinType> has key, store {
        deposit_amount: u64,
        borrowed_amount: u64,
        supply_interest: u64,
        borrow_interest: u64,
        supply_index: u64,
        borrow_index: u64,
        latest_timestamp: u64
    }

    public entry fun deposit<CoinType>(account: &signer, amount: u64) acquires Alcove {
        // refresh the pool first
        Pool::refresh();
        // then user's ticket
        refresh_account(signer::address_of(account));
        // check ticket exists
        if (!exists<Alcove<CoinType>>(signer::address_of(account))) {
            move_to(account, Alcove<CoinType>{
                deposit_amount: 0u64,
                borrowed_amount: 0u64,
                supply_interest: 0u64,
                borrow_interest: 0u64,
                supply_index: 0u64,
                borrow_index: 0u64,
                latest_timestamp: timestamp::now_seconds()
            })
        };
        // check amount enough
        assert!(coin::balance<CoinType>(signer::address_of(account)) >= amount, EACCOUNT_VALUE);
        // transfer to pool, call pool deposit method
        Pool::deposit<CoinType>(account, amount);
        // modify user's struct
        let ticket = borrow_global_mut<Alcove<CoinType>>(signer::address_of(account));
        ticket.deposit_amount = ticket.deposit_amount + amount;
        let (supply_index_pool, _borrow_index_pool) = Pool::get_index<CoinType>();
        ticket.supply_index = supply_index_pool;
        ticket.latest_timestamp = timestamp::now_seconds();
    }

    public entry fun withdraw<CoinType>(account: &signer, amount: u64) acquires Alcove {
        // refresh the pool first
        Pool::refresh();
        // then user's ticket
        refresh_account(signer::address_of(account));
        // check total deposit value
        let total_deposit_market_value = total_deposit_value(signer::address_of(account));
        // check total borrowed value
        let total_borrowed_market_value = total_borrowed_value(signer::address_of(account));
        // health check
        // withdraw value equal deposit value minus borrowed value
        let withdraw_max_market_value = total_deposit_market_value - total_borrowed_market_value;
        // check cointype amount market value is valid
        let price = Price::price<CoinType>();
        let withdraw_market_value_wanted = price * amount;
        assert!(withdraw_market_value_wanted <= withdraw_max_market_value, EINVALID_WITHDRAW_AMOUNT);
        // if amount equal 0, withdraw max
        if (amount == 0) {
            withdraw_market_value_wanted =  withdraw_max_market_value;
        };
        // transition to coin amount
        let withdraw_amount = withdraw_market_value_wanted / price;
        let ticket = borrow_global_mut<Alcove<CoinType>>(signer::address_of(account));
        assert!(withdraw_amount <= ticket.deposit_amount, EINVALID_WITHDRAW_AMOUNT);
        Pool::withdraw<CoinType>(account, withdraw_amount);
        let (supply_index_pool, _borrow_index_pool) = Pool::get_index<CoinType>();
        ticket.supply_index = supply_index_pool;
        ticket.deposit_amount = ticket.deposit_amount - withdraw_amount;
        ticket.latest_timestamp = timestamp::now_seconds();
    }

    public entry fun repay<CoinType>(account: &signer, amount: u64) acquires Alcove {
        // refresh the pool first
        Pool::refresh();
        // then user's ticket
        refresh_account(signer::address_of(account));
        let ticket = borrow_global_mut<Alcove<CoinType>>(signer::address_of(account));
        // if amount equal 0, repay max
        if (amount == 0) {
            amount = ticket.borrowed_amount;
        };
        // check balance of account
        assert!(coin::balance<CoinType>(signer::address_of(account)) >= amount, EACCOUNT_VALUE);
        // check borrowed amount
        assert!(ticket.borrowed_amount >= amount, EINVALID_REPAY_AMOUNT);
        Pool::repay<CoinType>(account, amount);
        ticket.borrowed_amount = ticket.borrowed_amount - amount;
        ticket.latest_timestamp = timestamp::now_seconds();
    }

    public entry fun borrow<CoinType>(account: &signer, amount: u64) acquires Alcove {
        // refresh the pool first
        Pool::refresh();
        // then user's ticket
        refresh_account(signer::address_of(account));
        // check ticket exists
        if (!exists<Alcove<CoinType>>(signer::address_of(account))) {
            move_to(account, Alcove<CoinType>{
                deposit_amount: 0u64,
                borrowed_amount: 0u64,
                supply_interest: 0u64,
                borrow_interest: 0u64,
                supply_index: 1u64,
                borrow_index: 1u64,
                latest_timestamp: timestamp::now_seconds()
            })
        };
        // check total deposit market value
        let total_deposit_market_value = total_deposit_value(signer::address_of(account));
        // check total borrowed market value
        let total_borrowed_market_value = total_borrowed_value(signer::address_of(account));
        // health check
        // check wanted borrow amount market value
        let max_borrow_market_value = total_deposit_market_value - total_borrowed_market_value;
        // if amount equals 0, borrow max
        let price = Price::price<CoinType>();
        let wanted_borrow_market_value = amount * price;
        if (amount == 0) {
            wanted_borrow_market_value = max_borrow_market_value;
            amount = max_borrow_market_value / price;
        };
        assert!(max_borrow_market_value >= wanted_borrow_market_value, EINVALID_BORROW_AMOUNT);
        Pool::borrow<CoinType>(account, amount);
        let ticket = borrow_global_mut<Alcove<CoinType>>(signer::address_of(account));
        ticket.borrowed_amount = ticket.borrowed_amount + amount;
        ticket.latest_timestamp = timestamp::now_seconds();
    }

    fun refresh_account(account: address) acquires Alcove {
        refresh_ticket<ETH>(account);
        refresh_ticket<BTC>(account);
        refresh_ticket<aptos_coin::AptosCoin>(account);
    }

    fun refresh_ticket<CoinType>(account: address) acquires Alcove {
        let ticket = borrow_global_mut<Alcove<CoinType>>(account);
        let (pool_supply_index, pool_borrow_index) = Pool::get_index<CoinType>();
        let supply_interest_new = (ticket.deposit_amount + ticket.supply_interest) * pool_supply_index / ticket.supply_index;
        let borrow_interest_new = (ticket.borrowed_amount + ticket.borrow_interest) * pool_borrow_index / ticket.borrow_index;
        ticket.supply_interest = ticket.supply_interest + supply_interest_new;
        ticket.borrow_interest = ticket.borrow_interest + borrow_interest_new;
        ticket.supply_index = pool_supply_index;
        ticket.borrow_index = pool_borrow_index;
        ticket.latest_timestamp = timestamp::now_seconds();
    }

    fun total_deposit_value(account: address): u64 acquires Alcove {
        let total_market_value = 0u64;
        if (exists<Alcove<aptos_coin::AptosCoin>>(copy account)) {
            let ticket = borrow_global<Alcove<aptos_coin::AptosCoin>>(copy account);
            let price = Price::price<aptos_coin::AptosCoin>();
            total_market_value = ticket.deposit_amount * price + total_market_value;
        };
        if (exists<Alcove<BTC>>(copy account)) {
            let ticket = borrow_global<Alcove<BTC>>(copy account);
            let price = Price::price<BTC>();
            total_market_value = ticket.deposit_amount * price + total_market_value;
        };
        if (exists<Alcove<ETH>>(copy account)) {
            let ticket = borrow_global<Alcove<ETH>>(copy account);
            let price = Price::price<ETH>();
            total_market_value = ticket.deposit_amount * price + total_market_value;
        };
        total_market_value
    }

    fun total_borrowed_value(account: address): u64 acquires Alcove {
        let total_market_value = 0u64;
        if (exists<Alcove<aptos_coin::AptosCoin>>(account)) {
            let ticket = borrow_global<Alcove<aptos_coin::AptosCoin>>(account);
            let price = Price::price<aptos_coin::AptosCoin>();
            total_market_value = ticket.borrowed_amount * price + total_market_value;
        };
        if (exists<Alcove<BTC>>(account)) {
            let ticket = borrow_global<Alcove<BTC>>(account);
            let price = Price::price<BTC>();
            total_market_value = ticket.borrowed_amount * price + total_market_value;
        };
        if (exists<Alcove<ETH>>(account)) {
            let ticket = borrow_global<Alcove<ETH>>(account);
            let price = Price::price<ETH>();
            total_market_value = ticket.borrowed_amount * price + total_market_value;
        };
        total_market_value
    }

}